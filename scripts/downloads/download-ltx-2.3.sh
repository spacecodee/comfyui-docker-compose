#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MODEL_DOWNLOAD_SCRIPT="$ROOT_DIR/scripts/model-download.sh"

usage() {
  cat <<'EOF'
Download required models for LTX-2.3 into ComfyUI models folders.

Usage:
  ./scripts/downloads/download-ltx-2.3.sh [--force] [--token <hf_token>]
  ./scripts/downloads/download-ltx-2.3.sh -h | --help

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
  echo "[ltx-2.3] using explicit Hugging Face token"
elif [[ -n "${HF_TOKEN:-}" ]]; then
  echo "[ltx-2.3] using HF_TOKEN from environment"
else
  echo "[ltx-2.3] HF token not set; using anonymous download"
fi

download_hf_model() {
  local model_dir="$1"
  local output_name="$2"
  local url="$3"

  local model_key="$model_dir/$output_name"
  if [[ -n "${requested_models[$model_key]:-}" ]]; then
    echo "[ltx-2.3] duplicate model entry skipped: $model_key"
    return 0
  fi
  requested_models["$model_key"]=1

  local destination="$models_root/$model_key"
  if [[ -f "$destination" && "$force" != "true" ]]; then
    echo "[ltx-2.3] already exists, skipping: $destination"
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

echo "[ltx-2.3] models root: $models_root"

download_hf_model \
  checkpoints \
  ltx-2.3-22b-dev-fp8.safetensors \
  https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-dev-fp8.safetensors

download_hf_model \
  loras \
  ltx-2.3-22b-distilled-lora-384.safetensors \
  https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-lora-384.safetensors

download_hf_model \
  loras \
  gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors \
  https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/loras/gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors

download_hf_model \
  latent_upscale_models \
  ltx-2.3-spatial-upscaler-x2-1.1.safetensors \
  https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors

echo "[ltx-2.3] completed"