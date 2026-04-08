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

workflows_dir="$(resolve_path "${COMFY_WORKFLOWS_DIR:-./data/workflows}")"
editing_dir="$workflows_dir/editing"
input_dir="$(resolve_path "${COMFY_INPUT_DIR:-./data/input}")"
output_dir="$(resolve_path "${COMFY_OUTPUT_DIR:-./data/output}")"

mkdir -p "$workflows_dir" "$editing_dir" "$input_dir" "$output_dir"
touch "$workflows_dir/.gitkeep" "$editing_dir/.gitkeep" "$input_dir/.gitkeep" "$output_dir/.gitkeep"

echo "[prepare-data-dirs] ensured ComfyUI data folders"
echo "[prepare-data-dirs] workflows dir: $workflows_dir"
echo "[prepare-data-dirs] input dir: $input_dir"
echo "[prepare-data-dirs] output dir: $output_dir"
