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
      COMFY_USER_BIND|COMFY_WORKFLOWS_BIND)
        export "$key=$value"
        ;;
    esac
  done < <(grep -E '^(COMFY_USER_BIND|COMFY_WORKFLOWS_BIND)=' "$env_file" || true)
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

usage() {
  cat <<'EOF'
Usage: ./scripts/workflow-save.sh [--editing] [--name output.json] [source.json]

If source.json is omitted, the script copies the latest JSON from:
  <COMFY_USER_BIND>/default/workflows

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

workflows_dir="$(resolve_bind "${COMFY_WORKFLOWS_BIND:-./data/workflows}")"
editing_dir="$workflows_dir/editing"
user_workflows_dir="$(resolve_bind "${COMFY_USER_BIND:-./data/user}")/default/workflows"

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

cp "$source_file" "$target_dir/$output_name"

echo "[workflow-save] saved to: $target_dir/$output_name"
