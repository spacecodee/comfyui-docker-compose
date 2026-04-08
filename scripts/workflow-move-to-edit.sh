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

workflows_dir="$(resolve_path "${COMFY_WORKFLOWS_DIR:-./data/workflows}")"
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

source_abs="$(cd "$(dirname "$source_path")" && pwd)/$(basename "$source_path")"
destination_abs="$(cd "$(dirname "$destination_path")" && pwd)/$(basename "$destination_path")"

if [[ "$source_abs" == "$destination_abs" ]]; then
  echo "[workflow-move-to-edit] workflow is already in editing: $destination_path"
  exit 0
fi

mv "$source_path" "$destination_path"

echo "[workflow-move-to-edit] moved to: $destination_path"
