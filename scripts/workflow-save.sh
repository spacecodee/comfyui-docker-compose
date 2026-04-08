#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

load_env_vars

resolve_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf "%s" "$path_value"
  else
    printf "%s/%s" "$ROOT_DIR" "${path_value#./}"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./scripts/workflow-save.sh [--editing] [--name output.json] [source.json]

If source.json is omitted, the script copies the latest JSON from:
  <COMFYUI_DIR>/user/default/workflows

Options:
  --editing      Save directly into workflows/editing
  --name NAME    Output filename
EOF
}

save_to_editing=false
output_name=""
source_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --editing)
      save_to_editing=true
      shift
      ;;
    --name)
      output_name="${2:-}"
      if [[ -z "$output_name" ]]; then
        echo "Missing value for --name" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$source_file" ]]; then
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      source_file="$1"
      shift
      ;;
  esac
done

workflows_dir="$(resolve_path "${COMFY_WORKFLOWS_DIR:-./data/workflows}")"
editing_dir="$workflows_dir/editing"
comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"

if [[ -n "${COMFY_USER_WORKFLOWS_DIR:-}" ]]; then
  user_workflows_dir="$(resolve_path "${COMFY_USER_WORKFLOWS_DIR}")"
else
  user_workflows_dir="$comfy_dir/user/default/workflows"
fi

mkdir -p "$workflows_dir" "$editing_dir"

target_dir="$workflows_dir"
if [[ "$save_to_editing" == true ]]; then
  target_dir="$editing_dir"
fi

if [[ -z "$source_file" ]]; then
  source_file="$(ls -1t "$user_workflows_dir"/*.json 2>/dev/null | head -n 1 || true)"
  if [[ -z "$source_file" ]]; then
    echo "No workflow JSON found in $user_workflows_dir" >&2
    exit 1
  fi
fi

if [[ ! -f "$source_file" ]]; then
  if [[ -f "$ROOT_DIR/$source_file" ]]; then
    source_file="$ROOT_DIR/$source_file"
  else
    echo "Workflow source file not found: $source_file" >&2
    exit 1
  fi
fi

if [[ -z "$output_name" ]]; then
  output_name="$(basename "$source_file")"
fi

target_path="$target_dir/$output_name"

source_abs="$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")"
target_abs="$(cd "$(dirname "$target_path")" && pwd)/$(basename "$target_path")"

if [[ "$source_abs" == "$target_abs" ]]; then
  echo "[workflow-save] source and destination are the same file: $target_path"
  exit 0
fi

cp "$source_file" "$target_path"

echo "[workflow-save] saved to: $target_path"
