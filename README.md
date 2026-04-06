# comfyui-docker-compose

Proyecto para ejecutar ComfyUI en Docker Compose con enfoque reproducible para servidores remotos (por ejemplo Lightning AI), evitando dependencias del entorno conda del host.

## Objetivo

- Ejecutar ComfyUI en contenedor.
- Usar configuración estable por defecto para NVIDIA en CUDA 13 (`cu130`).
- Permitir canal opcional nightly (`cu132`) para pruebas de rendimiento.
- Persistir modelos, nodos personalizados y salidas con bind mounts del host.

## Incluye

- `Dockerfile`: imagen reproducible con ComfyUI fijado por referencia (`COMFYUI_REF`).
- `docker-compose.yml`: servicio base (usable en entorno local sin GPU).
- `docker-compose.gpu.yml`: override para ejecución con GPU NVIDIA.
- `scripts/run-comfyui.sh`: script de ejecución (`local` o `gpu`).
- `scripts/prepare-data-dirs.sh`: crea toda la estructura de carpetas de datos.
- `scripts/workflow-save.sh`: guarda workflows en carpeta local dedicada.
- `scripts/workflow-move-to-edit.sh`: mueve workflows a carpeta de edición ignorada por git.
- `scripts/update-comfyui-ref.sh`: actualiza automáticamente `COMFYUI_REF`.
- `scripts/verify-local.sh` y `scripts/verify-gpu.sh`: smoke tests.

## Requisitos

- Docker Engine 24+ (recomendado)
- Docker Compose plugin v2+

Para ejecución con GPU NVIDIA:

- Driver NVIDIA compatible instalado en el host.
- NVIDIA Container Toolkit instalado y operativo.

Comprobaciones útiles:

```bash
docker --version
docker compose version
nvidia-smi
```

## Inicio rápido

1. Copia variables de entorno:

```bash
cp .env.example .env
```

2. Ajusta en `.env` al menos:

- `LOCAL_UID` y `LOCAL_GID` (usa `id -u` y `id -g` para evitar permisos root en los archivos generados).
- `COMFY_*_BIND` para ubicar persistencia en el disco del servidor.
- `TORCH_CHANNEL` (`stable` o `nightly`).
- `COMFYUI_REF` (tag o commit de ComfyUI).

3. Ejecuta ComfyUI:

```bash
# Sin GPU (local)
./scripts/run-comfyui.sh local up

# Con GPU NVIDIA
./scripts/run-comfyui.sh gpu up
```

4. Logs:

```bash
./scripts/run-comfyui.sh local logs
# o
./scripts/run-comfyui.sh gpu logs
```

UI por defecto: `http://localhost:8188`

## Manager y Previews

### ComfyUI-Manager

- El contenedor instala `manager_requirements.txt` automáticamente cuando ese archivo está disponible.
- El arranque usa por defecto `--enable-manager`.

### Preview de alta calidad

- Por defecto se aplica `--preview-method auto`.
- Para previews TAESD de alta calidad, coloca estos archivos en `data/models/vae_approx`:
	- `taesd_decoder.pth`
	- `taesdxl_decoder.pth`
	- `taesd3_decoder.pth`
	- `taef1_decoder.pth`

Después reinicia ComfyUI y usa en `.env`:

```bash
COMFYUI_EXTRA_ARGS=--enable-manager --preview-method taesd
```

## Canales de PyTorch (NVIDIA)

Este repo sigue lo indicado por ComfyUI:

- Estable (por defecto):

```bash
pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130
```

- Nightly opcional:

```bash
pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu132
```

Aquí se controla con `TORCH_CHANNEL`:

- `TORCH_CHANNEL=stable` usa `cu130`.
- `TORCH_CHANNEL=nightly` usa nightly `cu132`.

Cuando cambies canal, reconstruye imagen:

```bash
./scripts/run-comfyui.sh local build --no-cache
```

## Estructura de carpetas y commits

Se crean automáticamente carpetas de uso de ComfyUI dentro de `data/`.

- Carpetas con `.gitkeep` (versionadas):
	- `data/models/checkpoints`
	- `data/models/vae`
	- `data/models/vae_approx`
	- `data/models/loras`
	- `data/models/text_encoders`
	- `data/models/diffusion_models`
	- `data/custom_nodes`
	- `data/input`
	- `data/output`
	- `data/user`
	- `data/temp`

Todo archivo nuevo dentro de esas carpetas queda ignorado por git (solo se mantiene `.gitkeep`).

- Carpeta de workflows (sin `.gitkeep`):
	- `data/workflows`
	- `data/workflows/editing`

Estas carpetas están ignoradas por git por diseño: lo que guardes ahí nunca pedirá commit.

## Workflows

Guardar workflow (si no pasas archivo, toma el último de `data/user/default/workflows`):

```bash
./scripts/workflow-save.sh
```

Guardar directamente en carpeta de edición:

```bash
./scripts/workflow-save.sh --editing
```

Mover un workflow existente a carpeta de edición:

```bash
./scripts/workflow-move-to-edit.sh mi_workflow.json
```

## Script para actualizar COMFYUI_REF

Actualizar a la última tag disponible:

```bash
./scripts/update-comfyui-ref.sh
```

Fijar una referencia concreta:

```bash
./scripts/update-comfyui-ref.sh --ref v0.9.2 --file .env
```

## Operación manual con compose

Uso local (sin GPU):

```bash
docker compose up --build -d
docker compose logs -f comfyui
```

UI por defecto: `http://localhost:8188`

Detener:

```bash
docker compose down
```

Uso en servidor con GPU (Lightning):

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up --build -d
docker compose -f docker-compose.yml -f docker-compose.gpu.yml logs -f comfyui
```

Detener:

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml down
```

## Smoke tests

```bash
./scripts/verify-local.sh
```

```bash
./scripts/verify-gpu.sh
```

## Persistencia (bind mounts)

Por defecto se montan estas rutas host (configurables en `.env`):

- `./data/models` -> `/opt/comfyui/models`
- `./data/custom_nodes` -> `/opt/comfyui/custom_nodes`
- `./data/input` -> `/opt/comfyui/input`
- `./data/output` -> `/opt/comfyui/output`
- `./data/user` -> `/opt/comfyui/user`
- `./data/temp` -> `/opt/comfyui/temp`
- `./data/workflows` -> `/opt/comfyui/workflows`

## Actualizar versión de ComfyUI

1. Actualiza ref:

```bash
./scripts/update-comfyui-ref.sh
```

2. Reconstruye:

```bash
docker compose build --no-cache comfyui
```

3. Levanta de nuevo el stack.

## Troubleshooting

### "Torch not compiled with CUDA enabled"

- Verifica que estás arrancando con override GPU (`docker-compose.gpu.yml`).
- Verifica que el host expone GPU al runtime (`nvidia-smi` en host y dentro del contenedor si aplica).
- Rebuild si cambiaste canal/versiones.

### Problemas de permisos en carpetas montadas

- Ajusta `LOCAL_UID` y `LOCAL_GID` en `.env` con los valores reales del usuario del host.

### ComfyUI levanta, pero no genera imágenes

- Comprueba que tienes modelos en `/opt/comfyui/models/checkpoints` (bind mount `COMFY_MODELS_BIND`).

## Notas

- En desarrollo local sin GPU, mantén `COMFY_PRECHECK_CUDA=false`.
- Para forzar validación CUDA al inicio en host GPU, usa `COMFY_PRECHECK_CUDA=true`.
