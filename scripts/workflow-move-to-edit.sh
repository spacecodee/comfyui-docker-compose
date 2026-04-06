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
      COMFY_WORKFLOWS_BIND)
        export "$key=$value"
        ;;
    esac
  done < <(grep -E '^(COMFY_WORKFLOWS_BIND)=' "$env_file" || true)
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
  echo "Usage: ./scripts/workflow-move-to-edit.sh <workflow.json|path/to/workflow.json>"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

workflows_dir="$(resolve_bind "${COMFY_WORKFLOWS_BIND:-./data/workflows}")"
editing_dir="$workflows_dir/editing"

mkdir -p "$editing_dir"

candidate="$1"
if [[ -f "$candidate" ]]; then
  source_path="$candidate"
elif [[ -f "$workflows_dir/$candidate" ]]; then
  source_path="$workflows_dir/$candidate"
else
  echo "Workflow not found: $candidate" >&2
  exit 1
fi

destination_path="$editing_dir/$(basename "$source_path")"
mv "$source_path" "$destination_path"

echo "[workflow-move-to-edit] moved to: $destination_path"
