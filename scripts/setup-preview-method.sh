#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-preview-method.sh [--method auto|taesd|latent2rgb|none] [--force]

Downloads TAESD decoder files into ComfyUI models/vae_approx when needed.

Behavior:
  - method taesd: download decoders.
  - method auto: download decoders (optional quality assets, useful if you later switch to taesd).
  - method latent2rgb|none: no download.

If --method is omitted, the script uses COMFYUI_PREVIEW_METHOD or parses
--preview-method from COMFYUI_EXTRA_ARGS in .env/.env.example.
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

resolve_preview_method() {
  if [[ -n "$1" ]]; then
    printf "%s" "$1"
    return
  fi

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

  printf "auto"
}

method_override=""
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)
      method_override="${2:-}"
      if [[ -z "$method_override" ]]; then
        echo "Missing value for --method" >&2
        exit 1
      fi
      shift 2
      ;;
    --force)
      force=true
      shift
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

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but was not found in PATH" >&2
  exit 1
fi

load_env_vars

comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
vae_approx_dir="$comfy_dir/models/vae_approx"
base_url="${COMFY_PREVIEW_MODELS_BASE_URL:-https://raw.githubusercontent.com/madebyollin/taesd/main}"
preview_method="$(resolve_preview_method "$method_override")"

case "$preview_method" in
  taesd|auto)
    ;;
  latent2rgb|none)
    echo "[preview-setup] preview method '$preview_method' does not require TAESD decoders; skipping"
    exit 0
    ;;
  *)
    echo "[preview-setup] unknown preview method '$preview_method'; expected auto|taesd|latent2rgb|none" >&2
    exit 1
    ;;
esac

mkdir -p "$vae_approx_dir"

decoder_files=(
  taesd_decoder.pth
  taesdxl_decoder.pth
  taesd3_decoder.pth
  taef1_decoder.pth
)

echo "[preview-setup] method: $preview_method"
echo "[preview-setup] target dir: $vae_approx_dir"

for model_file in "${decoder_files[@]}"; do
  source_url="$base_url/$model_file"
  target_path="$vae_approx_dir/$model_file"
  temp_path="${target_path}.part"

  if [[ -f "$target_path" && "$force" != true ]]; then
    echo "[preview-setup] exists, skipping: $target_path"
    continue
  fi

  echo "[preview-setup] downloading: $model_file"
  curl -fL --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 30 \
    --output "$temp_path" \
    "$source_url"

  mv -f "$temp_path" "$target_path"
done

echo "[preview-setup] done"