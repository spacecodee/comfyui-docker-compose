#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "[verify-gpu] created .env from .env.example"
fi

./scripts/prepare-data-dirs.sh

docker compose -f docker-compose.yml -f docker-compose.gpu.yml config > /dev/null
echo "[verify-gpu] docker compose GPU config OK"

docker compose -f docker-compose.yml -f docker-compose.gpu.yml build comfyui

docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d comfyui

trap 'docker compose -f docker-compose.yml -f docker-compose.gpu.yml down --remove-orphans' EXIT

sleep 8

docker compose -f docker-compose.yml -f docker-compose.gpu.yml exec comfyui python - <<'PY'
import torch
print(f"[verify-gpu] torch={torch.__version__}")
print(f"[verify-gpu] cuda_available={torch.cuda.is_available()}")
if not torch.cuda.is_available():
    raise SystemExit("[verify-gpu] CUDA is not available inside container")
print(f"[verify-gpu] device={torch.cuda.get_device_name(0)}")
PY

echo "[verify-gpu] success"
