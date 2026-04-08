#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MODEL_DOWNLOAD_SCRIPT="$ROOT_DIR/scripts/model-download.sh"

usage() {
  cat <<'EOF'
Download required models for Z-Image-Base into ComfyUI models folders.

Usage:
  ./scripts/downloads/download-z-image-base.sh [--force] [--token <hf_token>]
  ./scripts/downloads/download-z-image-base.sh -h | --help

Options:
  --force          Overwrite files if they already exist
  --token <token>  Hugging Face token override
  -h, --help       Show this help

Token behavior:
  - If --token is set, it is used.
  - Else if HF_TOKEN exists in .env/.env.example, it is used.
  - Else download runs without token.
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

if [[ ! -x "$MODEL_DOWNLOAD_SCRIPT" ]]; then
  echo "Missing executable script: $MODEL_DOWNLOAD_SCRIPT" >&2
  exit 1
fi

force=false
explicit_token=""
declare -A requested_models=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=true
      shift
      ;;
    --token)
      explicit_token="${2:-}"
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

load_env_vars

comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
if [[ -n "${COMFY_MODELS_DIR:-}" ]]; then
  models_root="$(resolve_path "${COMFY_MODELS_DIR}")"
else
  models_root="$comfy_dir/models"
fi

if [[ -n "$explicit_token" ]]; then
  echo "[z-image-base] using explicit Hugging Face token"
elif [[ -n "${HF_TOKEN:-}" ]]; then
  echo "[z-image-base] using HF_TOKEN from environment"
else
  echo "[z-image-base] HF token not set; using anonymous download"
fi

download_hf_model() {
  local model_dir="$1"
  local output_name="$2"
  local url="$3"

  local model_key="$model_dir/$output_name"
  if [[ -n "${requested_models[$model_key]:-}" ]]; then
    echo "[z-image-base] duplicate model entry skipped: $model_key"
    return 0
  fi
  requested_models["$model_key"]=1

  local destination="$models_root/$model_key"
  if [[ -f "$destination" && "$force" != "true" ]]; then
    echo "[z-image-base] already exists, skipping: $destination"
    return 0
  fi

  local cmd=(
    "$MODEL_DOWNLOAD_SCRIPT"
    --provider huggingface
    --model-dir "$model_dir"
    --url "$url"
    --output "$output_name"
  )

  if [[ -n "$explicit_token" ]]; then
    cmd+=(--token "$explicit_token")
  fi

  if [[ "$force" == "true" ]]; then
    cmd+=(--force)
  fi

  "${cmd[@]}"
}

echo "[z-image-base] models root: $models_root"

download_hf_model \
  text_encoders \
  qwen_3_4b.safetensors \
  https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors

download_hf_model \
  diffusion_models \
  z_image_bf16.safetensors \
  https://huggingface.co/Comfy-Org/z_image/resolve/main/split_files/diffusion_models/z_image_bf16.safetensors

download_hf_model \
  vae \
  ae.safetensors \
  https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors

echo "[z-image-base] completed"