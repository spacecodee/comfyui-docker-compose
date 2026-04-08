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

case "$use_venv" in
  true|false)
    ;;
  *)
    echo "[run-comfyui] COMFY_USE_VENV must be 'true' or 'false' (current: $use_venv)" >&2
    exit 1
    ;;
esac

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
