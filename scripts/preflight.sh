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
MANAGER_ENFORCE_CONFIG="${COMFY_MANAGER_ENFORCE_CONFIG:-true}"
MANAGER_SECURITY_LEVEL="${COMFY_MANAGER_SECURITY_LEVEL:-normal}"
MANAGER_NETWORK_MODE="${COMFY_MANAGER_NETWORK_MODE:-personal_cloud}"
MANAGER_CONFIG_PATH="${COMFY_MANAGER_CONFIG_PATH:-${USER_DIR}/__manager/config.ini}"
MANAGER_CONFIG_DIR="$(dirname "$MANAGER_CONFIG_PATH")"

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
  "$MANAGER_CONFIG_DIR"
)

echo "[preflight] python: $(python --version 2>&1)"

for dir in "${required_dirs[@]}"; do
  mkdir -p "$dir"
  if [[ ! -w "$dir" ]]; then
    echo "[preflight] ERROR: directory is not writable: $dir" >&2
    exit 1
  fi
done

/usr/local/bin/install-custom-node-deps.sh

if [[ "$MANAGER_ENFORCE_CONFIG" == "true" ]]; then
  MANAGER_CONFIG_PATH="$MANAGER_CONFIG_PATH" \
  MANAGER_SECURITY_LEVEL="$MANAGER_SECURITY_LEVEL" \
  MANAGER_NETWORK_MODE="$MANAGER_NETWORK_MODE" \
  python - <<'PY'
import configparser
import os

config_path = os.environ["MANAGER_CONFIG_PATH"]
security_level = os.environ["MANAGER_SECURITY_LEVEL"]
network_mode = os.environ["MANAGER_NETWORK_MODE"]

config = configparser.ConfigParser(strict=False)
if os.path.exists(config_path):
    config.read(config_path)

if "default" not in config:
    config["default"] = {}

config["default"]["security_level"] = security_level
config["default"]["network_mode"] = network_mode

with open(config_path, "w", encoding="utf-8") as f:
    config.write(f)

print(f"[preflight] manager config updated: {config_path}")
print(f"[preflight] manager security_level={security_level}, network_mode={network_mode}")
PY
fi

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

python - <<'PY'
checks = [
  ("cv2", "import cv2"),
  ("diffusers", "import diffusers"),
  ("diffusers.configuration_utils", "from diffusers.configuration_utils import ConfigMixin"),
  ("diffusers.models.modeling_utils", "from diffusers.models.modeling_utils import ModelMixin"),
  ("transformers", "import transformers"),
  ("peft", "import peft"),
]

for name, stmt in checks:
  try:
    exec(stmt, {})
    print(f"[preflight] import_ok={name}")
  except Exception as exc:
    print(f"[preflight] WARNING: import_failed={name}: {exc}")
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
