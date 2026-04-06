#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./scripts/run-comfyui.sh [local|gpu] [up|down|logs|build|restart|ps]

Examples:
  ./scripts/run-comfyui.sh local up
  ./scripts/run-comfyui.sh gpu up
  ./scripts/run-comfyui.sh gpu logs
EOF
}

mode="${1:-local}"
action="${2:-up}"

if [[ $# -gt 0 ]]; then
  shift
fi
if [[ $# -gt 0 ]]; then
  shift
fi

extra_args=("$@")

case "$mode" in
  local) compose_cmd=(docker compose -f docker-compose.yml) ;;
  gpu) compose_cmd=(docker compose -f docker-compose.yml -f docker-compose.gpu.yml) ;;
  -h|--help) usage; exit 0 ;;
  *)
    echo "Unknown mode: $mode" >&2
    usage
    exit 1
    ;;
esac

./scripts/prepare-data-dirs.sh

case "$action" in
  up)
    "${compose_cmd[@]}" up --build -d "${extra_args[@]}"
    ;;
  down)
    "${compose_cmd[@]}" down "${extra_args[@]}"
    ;;
  logs)
    "${compose_cmd[@]}" logs -f comfyui "${extra_args[@]}"
    ;;
  build)
    "${compose_cmd[@]}" build comfyui "${extra_args[@]}"
    ;;
  restart)
    "${compose_cmd[@]}" down
    "${compose_cmd[@]}" up --build -d
    ;;
  ps)
    "${compose_cmd[@]}" ps
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown action: $action" >&2
    usage
    exit 1
    ;;
esac
