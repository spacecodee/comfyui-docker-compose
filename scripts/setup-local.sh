#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-local.sh [--ref <ref>] [--repo <url>]

Clones/updates ComfyUI inside this repository and installs Python
dependencies in the selected Python environment.
When enabled in .env, preview decoder models are also downloaded.

You can set COMFY_PYTHON_BIN in .env to choose a specific Python binary,
for example: python3.13
Set COMFY_USE_VENV=false in .env when running in environments that block
virtualenv creation (for example managed Studio/conda setups).
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
    echo "[setup-local] moved existing $label dir to: $backup"
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

validate_bool_setting() {
  local var_name="$1"
  local var_value="$2"

  case "$var_value" in
    true|false)
      ;;
    *)
      echo "[setup-local] $var_name must be 'true' or 'false' (current: $var_value)" >&2
      exit 1
      ;;
  esac
}

manager_enabled_from_env() {
  local extra="${COMFYUI_EXTRA_ARGS:-}"
  [[ "$extra" =~ (^|[[:space:]])--enable-manager([=[:space:]]|$) ]]
}

override_ref=""
override_repo=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      override_ref="${2:-}"
      if [[ -z "$override_ref" ]]; then
        echo "Missing value for --ref" >&2
        exit 1
      fi
      shift 2
      ;;
    --repo)
      override_repo="${2:-}"
      if [[ -z "$override_repo" ]]; then
        echo "Missing value for --repo" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but was not found in PATH" >&2
  exit 1
fi

load_env_vars

python_cmd="${COMFY_PYTHON_BIN:-python3}"
use_venv="${COMFY_USE_VENV:-true}"
auto_install_manager_requirements="${COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS:-true}"
auto_install_matrix_nio="${COMFY_AUTO_INSTALL_MATRIX_NIO:-true}"

validate_bool_setting "COMFY_USE_VENV" "$use_venv"
validate_bool_setting "COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS" "$auto_install_manager_requirements"
validate_bool_setting "COMFY_AUTO_INSTALL_MATRIX_NIO" "$auto_install_matrix_nio"

if ! command -v "$python_cmd" >/dev/null 2>&1; then
  echo "$python_cmd is required but was not found in PATH" >&2
  echo "Set COMFY_PYTHON_BIN in .env to a valid Python binary (for example python3.13)." >&2
  exit 1
fi

read -r py_major py_minor py_patch < <("$python_cmd" - <<'PY'
import sys
print(sys.version_info.major, sys.version_info.minor, sys.version_info.micro)
PY
)

if [[ -z "${py_major:-}" || -z "${py_minor:-}" || -z "${py_patch:-}" ]]; then
  echo "[setup-local] failed to detect Python version from $python_cmd" >&2
  exit 1
fi

if [[ "$py_major" != "3" ]]; then
  echo "[setup-local] Python 3 is required, but $python_cmd resolved to ${py_major}.${py_minor}.${py_patch}" >&2
  exit 1
fi

py_version="${py_major}.${py_minor}.${py_patch}"
py_major_minor="${py_major}.${py_minor}"

case "$py_major_minor" in
  3.13)
    echo "[setup-local] python=$py_version (very well supported)"
    ;;
  3.12)
    echo "[setup-local] python=$py_version (good fallback if some custom node deps fail on 3.13)"
    ;;
  3.14)
    echo "[setup-local] python=$py_version (works, but some custom nodes may have issues)"
    echo "[setup-local] note: free-threaded Python is not fully supported because some deps enable the GIL"
    ;;
  *)
    echo "[setup-local] python=$py_version"
    echo "[setup-local] recommendation: use Python 3.13, or 3.12 if dependency issues appear"
    ;;
esac

repo_url="${override_repo:-${COMFYUI_REPO_URL:-https://github.com/Comfy-Org/ComfyUI.git}}"
comfy_ref="${override_ref:-${COMFYUI_REF:-master}}"
comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
venv_dir="$(resolve_path "${COMFY_VENV_DIR:-./.venv}")"
workflows_dir="$(resolve_path "${COMFY_WORKFLOWS_DIR:-./data/workflows}")"
input_dir="$(resolve_path "${COMFY_INPUT_DIR:-./data/input}")"
output_dir="$(resolve_path "${COMFY_OUTPUT_DIR:-./data/output}")"

./scripts/prepare-data-dirs.sh

if [[ ! -d "$comfy_dir/.git" ]]; then
  echo "[setup-local] cloning ComfyUI into: $comfy_dir"
  git clone "$repo_url" "$comfy_dir"
else
  echo "[setup-local] ComfyUI already exists in: $comfy_dir"
  git -C "$comfy_dir" remote set-url origin "$repo_url"
fi

git -C "$comfy_dir" fetch --tags --prune origin

if git -C "$comfy_dir" rev-parse --verify --quiet "origin/${comfy_ref}^{commit}" >/dev/null; then
  git -C "$comfy_dir" checkout -B "$comfy_ref" "origin/$comfy_ref"
elif git -C "$comfy_dir" rev-parse --verify --quiet "${comfy_ref}^{commit}" >/dev/null; then
  git -C "$comfy_dir" checkout "$comfy_ref"
else
  echo "[setup-local] could not resolve COMFYUI_REF=$comfy_ref" >&2
  exit 1
fi

if [[ "$use_venv" == "true" && ! -x "$venv_dir/bin/python" ]]; then
  echo "[setup-local] creating virtual environment in: $venv_dir"
  venv_error_log="$(mktemp)"
  if ! "$python_cmd" -m venv "$venv_dir" 2>"$venv_error_log"; then
    venv_error_output="$(cat "$venv_error_log")"
    rm -f "$venv_error_log"

    if [[ "$venv_error_output" == *"Venv creation is not allowed"* || "$venv_error_output" == *"default conda environment"* ]]; then
      echo "[setup-local] virtualenv creation is blocked by this environment; using existing Python environment instead." >&2
      echo "[setup-local] tip: set COMFY_USE_VENV=false in .env to skip venv creation attempts." >&2
      use_venv=false
    else
      echo "[setup-local] failed to create virtual environment at: $venv_dir" >&2
      if [[ -n "$venv_error_output" ]]; then
        echo "$venv_error_output" >&2
      fi
      exit 1
    fi
  else
    rm -f "$venv_error_log"
  fi
fi

if [[ "$use_venv" == "true" ]]; then
  python_bin="$venv_dir/bin/python"
  if [[ ! -x "$python_bin" ]]; then
    echo "[setup-local] python not found in virtual environment: $python_bin" >&2
    exit 1
  fi
else
  python_bin="$(command -v "$python_cmd")"
  echo "[setup-local] using existing Python environment: $python_bin"
fi

echo "[setup-local] installing Python dependencies"
"$python_bin" -m pip install --upgrade pip setuptools wheel
"$python_bin" -m pip install -r "$comfy_dir/requirements.txt"

if manager_enabled_from_env && [[ "$auto_install_manager_requirements" == "true" ]] && [[ -f "$comfy_dir/manager_requirements.txt" ]]; then
  echo "[setup-local] installing ComfyUI manager requirements"
  "$python_bin" -m pip install -r "$comfy_dir/manager_requirements.txt"
fi

if manager_enabled_from_env && [[ "$auto_install_matrix_nio" == "true" ]]; then
  if ! "$python_bin" - <<'PY' >/dev/null 2>&1
import nio  # noqa: F401
PY
  then
    echo "[setup-local] installing matrix-nio for ComfyUI-Manager matrix sharing"
    if ! "$python_bin" -m pip install matrix-nio; then
      echo "[setup-local] warning: failed to install matrix-nio; matrix sharing will stay disabled" >&2
    fi
  fi
fi

if [[ "${COMFY_PREVIEW_AUTO_SETUP:-true}" == "true" ]]; then
  if ! ./scripts/setup-preview-method.sh; then
    echo "[setup-local] warning: preview decoder setup failed; continue with manual setup if needed" >&2
  fi
fi

ensure_runtime_links "$comfy_dir" "$workflows_dir" "$input_dir" "$output_dir"

echo "[setup-local] ready"
echo "[setup-local] run: ./scripts/run-comfyui.sh start"