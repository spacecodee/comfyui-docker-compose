#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

load_env_vars() {
  local env_file=""
  if [[ -f .env ]]; then
    env_file=.env
  elif [[ -f .env.example ]]; then
    env_file=.env.example
  fi

  if [[ -z "$env_file" ]]; then
    return 0
  fi

  while IFS='=' read -r key value; do
    value="${value%$'\r'}"
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      COMFY_MODELS_BIND|COMFY_CUSTOM_NODES_BIND|COMFY_INPUT_BIND|COMFY_OUTPUT_BIND|COMFY_USER_BIND|COMFY_TEMP_BIND|COMFY_WORKFLOWS_BIND)
        export "$key=$value"
        ;;
    esac
  done < <(grep -E '^(COMFY_MODELS_BIND|COMFY_CUSTOM_NODES_BIND|COMFY_INPUT_BIND|COMFY_OUTPUT_BIND|COMFY_USER_BIND|COMFY_TEMP_BIND|COMFY_WORKFLOWS_BIND)=' "$env_file" || true)
}

load_env_vars

resolve_bind() {
  local bind_path="$1"
  if [[ "$bind_path" = /* ]]; then
    printf "%s" "$bind_path"
  else
    printf "%s/%s" "$ROOT_DIR" "${bind_path#./}"
  fi
}

models_bind="$(resolve_bind "${COMFY_MODELS_BIND:-./data/models}")"
custom_nodes_bind="$(resolve_bind "${COMFY_CUSTOM_NODES_BIND:-./data/custom_nodes}")"
input_bind="$(resolve_bind "${COMFY_INPUT_BIND:-./data/input}")"
output_bind="$(resolve_bind "${COMFY_OUTPUT_BIND:-./data/output}")"
user_bind="$(resolve_bind "${COMFY_USER_BIND:-./data/user}")"
temp_bind="$(resolve_bind "${COMFY_TEMP_BIND:-./data/temp}")"
workflows_bind="$(resolve_bind "${COMFY_WORKFLOWS_BIND:-./data/workflows}")"

tracked_dirs=(
  "$models_bind/checkpoints"
  "$models_bind/vae"
  "$models_bind/vae_approx"
  "$models_bind/loras"
  "$models_bind/text_encoders"
  "$models_bind/diffusion_models"
  "$custom_nodes_bind"
  "$input_bind"
  "$output_bind"
  "$user_bind"
  "$temp_bind"
)

for dir in "${tracked_dirs[@]}"; do
  mkdir -p "$dir"
  touch "$dir/.gitkeep"
done

mkdir -p "$workflows_bind/editing"

echo "[prepare-data-dirs] ensured ComfyUI data folders"
echo "[prepare-data-dirs] workflows dir: $workflows_bind"
