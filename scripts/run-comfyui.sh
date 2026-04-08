#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run-comfyui.sh setup [--ref <ref>] [--repo <url>]
  ./scripts/run-comfyui.sh start [-- <extra ComfyUI args>]
  ./scripts/run-comfyui.sh deps
  ./scripts/run-comfyui.sh preview [--method <method>] [--force]
  ./scripts/run-comfyui.sh model-download [download-options]
  ./scripts/run-comfyui.sh -h | --help

Defaults:
  - Action: start
  - Host/port and extra args are read from .env or .env.example
EOF
}

load_env_vars() {
  local env_file=""
  if [[ -f "$ROOT_DIR/.env" ]]; then
    env_file="$ROOT_DIR/.env"
  elif [[ -f "$ROOT_DIR/.env.example" ]]; then
    env_file="$ROOT_DIR/.env.example"
  fi

  if [[ -z "$env_file" ]]; then
    return 0
  fi

  while IFS='=' read -r key value; do
    value="${value%$'\r'}"
    value="${value%\"}"
    value="${value#\"}"
    export "$key=$value"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" || true)
}

resolve_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf "%s" "$path_value"
  else
    printf "%s/%s" "$ROOT_DIR" "${path_value#./}"
  fi
}

ensure_symlink() {
  local source_dir="$1"
  local target_path="$2"
  local label="$3"

  mkdir -p "$(dirname "$target_path")"

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    local backup="${target_path}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$target_path" "$backup"
    echo "[run-comfyui] moved existing $label dir to: $backup"
  fi

  ln -sfn "$source_dir" "$target_path"
}

ensure_runtime_links() {
  local comfy_dir="$1"
  local workflows_dir="$2"
  local input_dir="$3"
  local output_dir="$4"

  ensure_symlink "$workflows_dir" "$comfy_dir/user/default/workflows" "workflows"
  ensure_symlink "$input_dir" "$comfy_dir/input" "input"
  ensure_symlink "$output_dir" "$comfy_dir/output" "output"
}

resolve_preview_method() {
  if [[ -n "${COMFYUI_PREVIEW_METHOD:-}" ]]; then
    printf "%s" "${COMFYUI_PREVIEW_METHOD}"
    return
  fi

  local extra="${COMFYUI_EXTRA_ARGS:-}"
  if [[ "$extra" =~ --preview-method[[:space:]]+([^[:space:]]+) ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$extra" =~ --preview-method=([^[:space:]]+) ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
    return
  fi

  printf ""
}

extra_args_has_preview_flag() {
  local extra="${COMFYUI_EXTRA_ARGS:-}"
  [[ "$extra" =~ (^|[[:space:]])--preview-method([=[:space:]]|$) ]]
}

validate_bool_setting() {
  local var_name="$1"
  local var_value="$2"

  case "$var_value" in
    true|false)
      ;;
    *)
      echo "[run-comfyui] $var_name must be 'true' or 'false' (current: $var_value)" >&2
      exit 1
      ;;
  esac
}

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

sync_requirements_if_needed() {
  local requirements_file="$1"
  local state_file="$2"
  local label="$3"
  local enabled="$4"

  if [[ "$enabled" != "true" ]]; then
    return 0
  fi

  if [[ ! -f "$requirements_file" ]]; then
    return 0
  fi

  local current_hash
  current_hash="$(file_sha256 "$requirements_file")"

  local previous_hash=""
  if [[ -f "$state_file" ]]; then
    previous_hash="$(tr -d '\r\n' < "$state_file" || true)"
  fi

  if [[ -n "$previous_hash" && "$previous_hash" == "$current_hash" ]]; then
    return 0
  fi

  echo "[run-comfyui] syncing $label"
  "$python_bin" -m pip install -r "$requirements_file"

  mkdir -p "$(dirname "$state_file")"
  printf "%s\n" "$current_hash" > "$state_file"
}

manager_enabled_for_start() {
  local merged="${COMFYUI_EXTRA_ARGS:-}"
  local arg

  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      continue
    fi
    merged+=" $arg"
  done

  [[ "$merged" =~ (^|[[:space:]])--enable-manager([=[:space:]]|$) ]]
}

repair_torchaudio_if_needed() {
  local enabled="$1"

  if [[ "$enabled" != "true" ]]; then
    return 0
  fi

  local check_output
  local check_status

  set +e
  check_output="$("$python_bin" - <<'PY'
import sys

try:
    import torch
    print(f"TORCH_VERSION={torch.__version__}")
except Exception as exc:
    print(f"TORCH_IMPORT_ERROR={exc}")
    raise SystemExit(2)

try:
    import torchaudio  # noqa: F401
    print("TORCHAUDIO_OK=1")
except Exception as exc:
    print("TORCHAUDIO_OK=0")
    print(f"TORCHAUDIO_ERROR={exc}")
    raise SystemExit(1)
PY
)"
  check_status=$?
  set -e

  if [[ "$check_status" -eq 0 ]]; then
    return 0
  fi

  if [[ "$check_status" -eq 2 ]]; then
    echo "[run-comfyui] warning: torch import failed; skipping torchaudio auto-repair" >&2
    return 0
  fi

  local torch_version
  local torchaudio_error
  torch_version="$(printf '%s\n' "$check_output" | grep '^TORCH_VERSION=' | head -n 1 | cut -d'=' -f2- || true)"
  torchaudio_error="$(printf '%s\n' "$check_output" | grep '^TORCHAUDIO_ERROR=' | head -n 1 | cut -d'=' -f2- || true)"

  echo "[run-comfyui] torchaudio import failed: ${torchaudio_error:-unknown error}" >&2

  if [[ -z "$torch_version" ]]; then
    echo "[run-comfyui] warning: could not resolve torch version; skipping torchaudio auto-repair" >&2
    return 0
  fi

  local torch_base
  local torch_build=""
  local torchaudio_spec

  torch_base="${torch_version%%+*}"
  if [[ "$torch_version" == *"+"* ]]; then
    torch_build="${torch_version#*+}"
  fi

  if [[ "$torch_base" == *"dev"* ]]; then
    torchaudio_spec="torchaudio"
  else
    torchaudio_spec="torchaudio==${torch_base}"
  fi

  echo "[run-comfyui] attempting torchaudio repair for torch=$torch_version"

  local repaired=false
  if [[ "$torch_build" =~ ^(cu[0-9]+|cpu)$ ]]; then
    if "$python_bin" -m pip install --upgrade --force-reinstall "$torchaudio_spec" --index-url "https://download.pytorch.org/whl/$torch_build"; then
      repaired=true
    fi
  fi

  if [[ "$repaired" != "true" ]]; then
    if "$python_bin" -m pip install --upgrade --force-reinstall "$torchaudio_spec"; then
      repaired=true
    fi
  fi

  if [[ "$repaired" != "true" ]]; then
    echo "[run-comfyui] warning: torchaudio auto-repair failed; audio nodes may remain unavailable" >&2
    return 0
  fi

  set +e
  "$python_bin" - <<'PY'
import torchaudio  # noqa: F401
print("[run-comfyui] torchaudio import check passed after repair")
PY
  check_status=$?
  set -e

  if [[ "$check_status" -ne 0 ]]; then
    echo "[run-comfyui] warning: torchaudio is still failing after repair; audio nodes may remain unavailable" >&2
  fi
}

action="start"
if [[ $# -gt 0 ]]; then
  case "$1" in
    setup|start|deps|preview|model-download)
      action="$1"
      shift
      ;;
    local|gpu|up|down|logs|build|restart|ps)
      echo "[run-comfyui] Docker-style actions are no longer supported." >&2
      echo "[run-comfyui] use: ./scripts/run-comfyui.sh setup" >&2
      echo "[run-comfyui] then: ./scripts/run-comfyui.sh start" >&2
      exit 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

load_env_vars

comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
venv_dir="$(resolve_path "${COMFY_VENV_DIR:-./.venv}")"
workflows_dir="$(resolve_path "${COMFY_WORKFLOWS_DIR:-./data/workflows}")"
input_dir="$(resolve_path "${COMFY_INPUT_DIR:-./data/input}")"
output_dir="$(resolve_path "${COMFY_OUTPUT_DIR:-./data/output}")"
python_cmd="${COMFY_PYTHON_BIN:-python3}"
use_venv="${COMFY_USE_VENV:-true}"
auto_sync_requirements="${COMFY_AUTO_SYNC_REQUIREMENTS:-true}"
auto_install_manager_requirements="${COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS:-true}"
auto_fix_torchaudio="${COMFY_AUTO_FIX_TORCHAUDIO:-true}"
cli_extra_args=("$@")

case "$action" in
  setup)
    exec ./scripts/setup-local.sh "$@"
    ;;
  deps)
    exec ./scripts/install-custom-node-deps.sh --manual
    ;;
  preview)
    exec ./scripts/setup-preview-method.sh "$@"
    ;;
  model-download)
    exec ./scripts/model-download.sh "$@"
    ;;
  start)
    ;;
  *)
    echo "Unknown action: $action" >&2
    usage
    exit 1
    ;;
esac

if [[ ! -f "$comfy_dir/main.py" ]]; then
  echo "[run-comfyui] ComfyUI not found in: $comfy_dir" >&2
  echo "[run-comfyui] run: ./scripts/run-comfyui.sh setup" >&2
  exit 1
fi

validate_bool_setting "COMFY_USE_VENV" "$use_venv"
validate_bool_setting "COMFY_AUTO_SYNC_REQUIREMENTS" "$auto_sync_requirements"
validate_bool_setting "COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS" "$auto_install_manager_requirements"
validate_bool_setting "COMFY_AUTO_FIX_TORCHAUDIO" "$auto_fix_torchaudio"

if [[ "$use_venv" == "true" && -x "$venv_dir/bin/python" ]]; then
  python_bin="$venv_dir/bin/python"
elif command -v "$python_cmd" >/dev/null 2>&1; then
  python_bin="$(command -v "$python_cmd")"
  if [[ "$use_venv" == "true" ]]; then
    echo "[run-comfyui] virtualenv not found in: $venv_dir" >&2
    echo "[run-comfyui] falling back to existing Python environment: $python_bin" >&2
    echo "[run-comfyui] tip: set COMFY_USE_VENV=false in .env for managed environments." >&2
  fi
else
  echo "[run-comfyui] python command not found: $python_cmd" >&2
  if [[ "$use_venv" == "true" ]]; then
    echo "[run-comfyui] run: ./scripts/run-comfyui.sh setup" >&2
  fi
  exit 1
fi

sync_requirements_if_needed \
  "$comfy_dir/requirements.txt" \
  "$comfy_dir/user/.cache/comfy-core-requirements.sha256" \
  "ComfyUI core requirements" \
  "$auto_sync_requirements"

if manager_enabled_for_start "${cli_extra_args[@]}"; then
  sync_requirements_if_needed \
    "$comfy_dir/manager_requirements.txt" \
    "$comfy_dir/user/.cache/comfy-manager-requirements.sha256" \
    "ComfyUI manager requirements" \
    "$auto_install_manager_requirements"
fi

repair_torchaudio_if_needed "$auto_fix_torchaudio"

./scripts/prepare-data-dirs.sh
ensure_runtime_links "$comfy_dir" "$workflows_dir" "$input_dir" "$output_dir"

if [[ "${COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS:-true}" == "true" ]]; then
  ./scripts/install-custom-node-deps.sh
else
  echo "[run-comfyui] skipping custom node dependency auto-install"
fi

host="${COMFYUI_HOST:-127.0.0.1}"
port="${COMFYUI_PORT:-8188}"
args=(--listen "$host" --port "$port")

preview_method="$(resolve_preview_method)"
if [[ -n "$preview_method" && ! extra_args_has_preview_flag ]]; then
  args+=(--preview-method "$preview_method")
fi

if [[ -n "${COMFYUI_EXTRA_ARGS:-}" ]]; then
  read -r -a split_extra_args <<< "${COMFYUI_EXTRA_ARGS}"
  args+=("${split_extra_args[@]}")
fi

if [[ $# -gt 0 && "$1" == "--" ]]; then
  shift
fi

if [[ $# -gt 0 ]]; then
  args+=("$@")
fi

echo "[run-comfyui] starting ComfyUI from: $comfy_dir"
echo "[run-comfyui] args: ${args[*]}"

cd "$comfy_dir"
exec "$python_bin" main.py "${args[@]}"
