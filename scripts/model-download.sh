#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODEL_DIRS_FILE="$ROOT_DIR/scripts/comfy-model-dirs.txt"

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
      COMFY_MODELS_BIND|HF_TOKEN|CIVITAI_TOKEN)
        export "$key=$value"
        ;;
    esac
  done < <(grep -E '^(COMFY_MODELS_BIND|HF_TOKEN|CIVITAI_TOKEN)=' "$env_file" || true)
}

resolve_bind() {
  local bind_path="$1"
  if [[ "$bind_path" = /* ]]; then
    printf "%s" "$bind_path"
  else
    printf "%s/%s" "$ROOT_DIR" "${bind_path#./}"
  fi
}

print_valid_model_dirs() {
  echo "Valid model directories (ComfyUI models/*):"
  tr '\n' ' ' < "$MODEL_DIRS_FILE"
  echo
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/model-download.sh --provider huggingface --model-dir <dir> --repo <org/repo> --file <path/in/repo> [options]
  ./scripts/model-download.sh --provider civitai --model-dir <dir> --url <download-url> [options]
  ./scripts/model-download.sh --provider civitai --model-dir <dir> --model-id <version-id> [options]

Required:
  --provider      huggingface | civitai
  --model-dir     One folder from scripts/comfy-model-dirs.txt

Hugging Face options:
  --repo          e.g. runwayml/stable-diffusion-v1-5
  --file          e.g. v1-5-pruned-emaonly-fp16.safetensors
  --revision      Branch/tag/commit (default: main)

CivitAI options:
  --url           Full CivitAI download URL
  --model-id      CivitAI model version ID (builds api/download/models/<id>)

General options:
  --output        Destination filename (optional)
  --token         API token (optional). If omitted, uses HF_TOKEN/CIVITAI_TOKEN env var.
  --force         Overwrite destination file if it already exists
  -h, --help      Show this help

Examples:
  ./scripts/model-download.sh --provider huggingface --model-dir checkpoints \
    --repo Comfy-Org/stable-diffusion-v1-5-archive \
    --file v1-5-pruned-emaonly-fp16.safetensors

  ./scripts/model-download.sh --provider civitai --model-dir loras \
    --model-id 12345 --output my_lora.safetensors
EOF
}

if [[ ! -f "$MODEL_DIRS_FILE" ]]; then
  echo "Missing model directories file: $MODEL_DIRS_FILE" >&2
  exit 1
fi

load_env_vars

provider=""
model_dir=""
repo=""
file_path=""
revision="main"
download_url=""
model_id=""
output_name=""
explicit_token=""
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --model-dir)
      model_dir="${2:-}"
      shift 2
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --file)
      file_path="${2:-}"
      shift 2
      ;;
    --revision)
      revision="${2:-}"
      shift 2
      ;;
    --url)
      download_url="${2:-}"
      shift 2
      ;;
    --model-id)
      model_id="${2:-}"
      shift 2
      ;;
    --output)
      output_name="${2:-}"
      shift 2
      ;;
    --token)
      explicit_token="${2:-}"
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

if [[ -z "$provider" || -z "$model_dir" ]]; then
  usage
  exit 1
fi

if ! grep -Fxq "$model_dir" "$MODEL_DIRS_FILE"; then
  echo "Invalid --model-dir: $model_dir" >&2
  print_valid_model_dirs
  exit 1
fi

case "$provider" in
  huggingface|civitai)
    ;;
  *)
    echo "Invalid --provider: $provider (use huggingface or civitai)" >&2
    exit 1
    ;;
esac

models_bind="$(resolve_bind "${COMFY_MODELS_BIND:-./data/models}")"
dest_dir="$models_bind/$model_dir"
mkdir -p "$dest_dir"

declare -a auth_headers
request_token=""

if [[ "$provider" == "huggingface" ]]; then
  request_token="$explicit_token"
  if [[ -z "$request_token" ]]; then
    request_token="${HF_TOKEN:-}"
  fi

  if [[ -z "$download_url" ]]; then
    if [[ -z "$repo" || -z "$file_path" ]]; then
      echo "Hugging Face requires --url or both --repo and --file" >&2
      exit 1
    fi
    download_url="https://huggingface.co/${repo}/resolve/${revision}/${file_path}"
  fi

  if [[ -n "$request_token" ]]; then
    auth_headers+=("-H" "Authorization: Bearer ${request_token}")
  fi
fi

if [[ "$provider" == "civitai" ]]; then
  request_token="$explicit_token"
  if [[ -z "$request_token" ]]; then
    request_token="${CIVITAI_TOKEN:-}"
  fi

  if [[ -z "$download_url" ]]; then
    if [[ -z "$model_id" ]]; then
      echo "CivitAI requires --url or --model-id" >&2
      exit 1
    fi
    download_url="https://civitai.com/api/download/models/${model_id}"
  fi

  if [[ -n "$request_token" && "$download_url" != *"token="* ]]; then
    if [[ "$download_url" == *"?"* ]]; then
      download_url="${download_url}&token=${request_token}"
    else
      download_url="${download_url}?token=${request_token}"
    fi
  fi
fi

infer_name_from_headers() {
  local header_name
  header_name="$(curl -fsSLI "${auth_headers[@]}" "$download_url" \
    | tr -d '\r' \
    | sed -n 's/.*[Ff]ilename="\{0,1\}\([^";]*\)"\{0,1\}.*/\1/p' \
    | tail -n 1 || true)"
  printf "%s" "$header_name"
}

if [[ -z "$output_name" ]]; then
  if [[ -n "$file_path" ]]; then
    output_name="$(basename "$file_path")"
  fi
fi

if [[ -z "$output_name" ]]; then
  output_name="$(infer_name_from_headers)"
fi

if [[ -z "$output_name" ]]; then
  output_name="$(basename "${download_url%%\?*}")"
fi

if [[ -z "$output_name" || "$output_name" == "/" || "$output_name" == "models" ]]; then
  output_name="downloaded-model-$(date +%s).bin"
fi

destination="$dest_dir/$output_name"
partial_file="${destination}.part"

if [[ -f "$destination" && "$force" != true ]]; then
  echo "Destination already exists: $destination" >&2
  echo "Use --force to overwrite." >&2
  exit 1
fi

echo "[model-download] provider: $provider"
echo "[model-download] destination: $destination"

echo "[model-download] downloading..."
curl -fL --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 30 \
  "${auth_headers[@]}" \
  --output "$partial_file" \
  "$download_url"

mv -f "$partial_file" "$destination"

if [[ ! -s "$destination" ]]; then
  echo "Downloaded file is empty: $destination" >&2
  exit 1
fi

echo "[model-download] done"
