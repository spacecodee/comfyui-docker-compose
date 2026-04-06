#!/usr/bin/env bash
set -Eeuo pipefail

MODELS_DIR="${COMFY_MODELS_DIR:-/opt/comfyui/models}"
CUSTOM_NODES_DIR="${COMFY_CUSTOM_NODES_DIR:-/opt/comfyui/custom_nodes}"
INPUT_DIR="${COMFY_INPUT_DIR:-/opt/comfyui/input}"
OUTPUT_DIR="${COMFY_OUTPUT_DIR:-/opt/comfyui/output}"
USER_DIR="${COMFY_USER_DIR:-/opt/comfyui/user}"
TEMP_DIR="${COMFY_TEMP_DIR:-/opt/comfyui/temp}"
WORKFLOWS_DIR="${COMFY_WORKFLOWS_DIR:-/opt/comfyui/workflows}"
WORKFLOWS_EDIT_DIR="${COMFY_WORKFLOWS_EDIT_DIR:-${WORKFLOWS_DIR}/editing}"
HOME_DIR="${HOME:-/opt/comfyui/user}"
XDG_CACHE_HOME_DIR="${XDG_CACHE_HOME:-${HOME_DIR}/.cache}"
TORCHINDUCTOR_CACHE_DIR_VALUE="${TORCHINDUCTOR_CACHE_DIR:-${XDG_CACHE_HOME_DIR}/torchinductor}"
PRECHECK_CUDA="${COMFY_PRECHECK_CUDA:-false}"

required_dirs=(
  "$MODELS_DIR"
  "$CUSTOM_NODES_DIR"
  "$INPUT_DIR"
  "$OUTPUT_DIR"
  "$USER_DIR"
  "$TEMP_DIR"
  "$WORKFLOWS_DIR"
  "$WORKFLOWS_EDIT_DIR"
  "$HOME_DIR"
  "$XDG_CACHE_HOME_DIR"
  "$TORCHINDUCTOR_CACHE_DIR_VALUE"
)

echo "[preflight] python: $(python --version 2>&1)"

for dir in "${required_dirs[@]}"; do
  mkdir -p "$dir"
  if [[ ! -w "$dir" ]]; then
    echo "[preflight] ERROR: directory is not writable: $dir" >&2
    exit 1
  fi
done

python - <<'PY'
import sys

try:
    import torch
except Exception as exc:
    print(f"[preflight] ERROR: could not import torch: {exc}", file=sys.stderr)
    raise SystemExit(1)

print(f"[preflight] torch={torch.__version__}")
print(f"[preflight] cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"[preflight] cuda_device_count={torch.cuda.device_count()}")
PY

if [[ "$PRECHECK_CUDA" == "true" ]]; then
  python - <<'PY'
import torch
import sys

if not torch.cuda.is_available():
    print("[preflight] ERROR: COMFY_PRECHECK_CUDA=true but CUDA is not available", file=sys.stderr)
    raise SystemExit(1)
PY
fi

echo "[preflight] environment OK"
