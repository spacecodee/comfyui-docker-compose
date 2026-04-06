#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "[verify-local] created .env from .env.example"
fi

./scripts/prepare-data-dirs.sh

docker compose config > /dev/null
echo "[verify-local] docker compose config OK"

docker compose build comfyui

docker compose up -d comfyui

trap 'docker compose down --remove-orphans' EXIT

sleep 8

curl -fsS "http://127.0.0.1:${COMFYUI_PORT:-8188}/" > /dev/null
echo "[verify-local] HTTP endpoint reachable"

docker compose exec comfyui python - <<'PY'
import torch
print(f"[verify-local] torch={torch.__version__}")
print(f"[verify-local] cuda_available={torch.cuda.is_available()}")
PY

echo "[verify-local] success"
