#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./scripts/update-comfyui-ref.sh [--ref vX.Y.Z|commit] [--file .env|.env.example]

If --ref is omitted, the script fetches the latest ComfyUI tag.
If --file is omitted, it uses .env when present, otherwise .env.example.
EOF
}

target_file=""
new_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      new_ref="${2:-}"
      if [[ -z "$new_ref" ]]; then
        echo "Missing value for --ref" >&2
        exit 1
      fi
      shift 2
      ;;
    --file)
      target_file="${2:-}"
      if [[ -z "$target_file" ]]; then
        echo "Missing value for --file" >&2
        exit 1
      fi
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

if [[ -z "$target_file" ]]; then
  if [[ -f "$ROOT_DIR/.env" ]]; then
    target_file="$ROOT_DIR/.env"
  else
    target_file="$ROOT_DIR/.env.example"
  fi
elif [[ "$target_file" != /* ]]; then
  target_file="$ROOT_DIR/${target_file#./}"
fi

if [[ ! -f "$target_file" ]]; then
  echo "Target file does not exist: $target_file" >&2
  exit 1
fi

if [[ -z "$new_ref" ]]; then
  new_ref="$(git ls-remote --tags --refs https://github.com/Comfy-Org/ComfyUI.git \
    | awk -F/ '{print $3}' \
    | sort -V \
    | tail -n 1)"
fi

if [[ -z "$new_ref" ]]; then
  echo "Could not resolve COMFYUI_REF" >&2
  exit 1
fi

old_ref="$(grep '^COMFYUI_REF=' "$target_file" | head -n 1 | cut -d'=' -f2- || true)"

if grep -q '^COMFYUI_REF=' "$target_file"; then
  sed -i "s|^COMFYUI_REF=.*|COMFYUI_REF=$new_ref|" "$target_file"
else
  printf "\nCOMFYUI_REF=%s\n" "$new_ref" >> "$target_file"
fi

echo "[update-comfyui-ref] file: $target_file"
echo "[update-comfyui-ref] old: ${old_ref:-<none>}"
echo "[update-comfyui-ref] new: $new_ref"
