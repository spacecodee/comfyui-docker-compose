#!/usr/bin/env bash
set -Eeuo pipefail

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
