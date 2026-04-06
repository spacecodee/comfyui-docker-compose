#!/usr/bin/env bash
set -Eeuo pipefail

runtime_user="${COMFY_RUNTIME_USER:-comfyui}"
export USER="${USER:-$runtime_user}"
export LOGNAME="${LOGNAME:-$runtime_user}"
export HOME="${HOME:-/opt/comfyui/user}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-${XDG_CACHE_HOME}/torchinductor}"

mkdir -p "$HOME" "$XDG_CACHE_HOME" "$TORCHINDUCTOR_CACHE_DIR"

/usr/local/bin/preflight.sh

cd /opt/comfyui

host="${COMFYUI_HOST:-0.0.0.0}"
port="${COMFYUI_PORT:-8188}"
if [[ -z "${COMFYUI_EXTRA_ARGS:-}" ]]; then
  extra_args="--enable-manager --preview-method auto"
else
  extra_args="${COMFYUI_EXTRA_ARGS}"
fi

args=(--listen "$host" --port "$port")

if [[ -n "$extra_args" ]]; then
  read -r -a split_extra_args <<< "$extra_args"
  args+=("${split_extra_args[@]}")
fi

if [[ "$#" -gt 0 ]]; then
  args+=("$@")
fi

echo "[entrypoint] starting ComfyUI with args: ${args[*]}"
exec python main.py "${args[@]}"
