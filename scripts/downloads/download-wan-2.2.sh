#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MODEL_DOWNLOAD_SCRIPT="$ROOT_DIR/scripts/model-download.sh"

usage() {
  cat <<'EOF'
Download required models for WAN 2.2 into ComfyUI models folders.

Usage:
  ./scripts/downloads/download-wan-2.2.sh [--mode <i2v|t2v|all>] [--force] [--token <hf_token>]
  ./scripts/downloads/download-wan-2.2.sh -h | --help

Options:
  --mode <value>   i2v, t2v, or all (default: all)
  --force          Overwrite files if they already exist
  --token <token>  Hugging Face token override
  -h, --help       Show this help

Token behavior:
  - If --token is set, it is used.
  - Else if HF_TOKEN exists in .env/.env.example, it is used.
  - Else download runs without token.

Notes:
  - This script de-duplicates repeated files across i2v/t2v sets.
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

mode="all"
force=false
explicit_token=""
declare -A requested_models=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="${2:-}"
      shift 2
      ;;
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

case "$mode" in
  i2v|t2v|all)
    ;;
  *)
    echo "Invalid --mode: $mode (use i2v, t2v, or all)" >&2
    exit 1
    ;;
esac

load_env_vars

comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
if [[ -n "${COMFY_MODELS_DIR:-}" ]]; then
  models_root="$(resolve_path "${COMFY_MODELS_DIR}")"
else
  models_root="$comfy_dir/models"
fi

if [[ -n "$explicit_token" ]]; then
  echo "[wan-2.2] using explicit Hugging Face token"
elif [[ -n "${HF_TOKEN:-}" ]]; then
  echo "[wan-2.2] using HF_TOKEN from environment"
else
  echo "[wan-2.2] HF token not set; using anonymous download"
fi

download_hf_model() {
  local model_dir="$1"
  local output_name="$2"
  local url="$3"

  local model_key="$model_dir/$output_name"
  if [[ -n "${requested_models[$model_key]:-}" ]]; then
    echo "[wan-2.2] duplicate model entry skipped: $model_key"
    return 0
  fi
  requested_models["$model_key"]=1

  local destination="$models_root/$model_key"
  if [[ -f "$destination" && "$force" != "true" ]]; then
    echo "[wan-2.2] already exists, skipping: $destination"
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

download_shared_models() {
  download_hf_model \
    vae \
    wan_2.1_vae.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors

  download_hf_model \
    text_encoders \
    umt5_xxl_fp8_e4m3fn_scaled.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
}

download_i2v_models() {
  download_hf_model \
    diffusion_models \
    wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors

  download_hf_model \
    diffusion_models \
    wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors

  download_hf_model \
    loras \
    wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors

  download_hf_model \
    loras \
    wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors
}

download_t2v_models() {
  download_hf_model \
    diffusion_models \
    wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors

  download_hf_model \
    diffusion_models \
    wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors

  download_hf_model \
    loras \
    wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors

  download_hf_model \
    loras \
    wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors \
    https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors
}

echo "[wan-2.2] models root: $models_root"
echo "[wan-2.2] mode: $mode"

download_shared_models

if [[ "$mode" == "all" || "$mode" == "i2v" ]]; then
  download_i2v_models
fi

if [[ "$mode" == "all" || "$mode" == "t2v" ]]; then
  download_t2v_models
fi

echo "[wan-2.2] completed"