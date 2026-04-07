# comfyui-docker-compose

Run ComfyUI with Docker Compose using a reproducible setup for remote servers (for example Lightning AI), without relying on the host conda environment.

## Goal

- Run ComfyUI in a container.
- Use a stable default for NVIDIA on CUDA 13 (`cu130`).
- Allow an optional nightly channel (`cu132`) for performance testing.
- Persist models, custom nodes, and outputs using host bind mounts.

## Includes

- `Dockerfile`: reproducible image with ComfyUI pinned by reference (`COMFYUI_REF`).
- `docker-compose.yml`: base service (usable locally without GPU).
- `docker-compose.gpu.yml`: override for NVIDIA GPU execution.
- `scripts/run-comfyui.sh`: run script (`local` or `gpu`).
- `scripts/prepare-data-dirs.sh`: creates the full data directory structure.
- `scripts/workflow-save.sh`: saves workflows into a dedicated local folder.
- `scripts/workflow-move-to-edit.sh`: moves workflows into an edit folder ignored by git.
- `scripts/update-comfyui-ref.sh`: automatically updates `COMFYUI_REF`.
- `scripts/model-download.sh`: downloads models from Hugging Face or CivitAI into ComfyUI model folders.
- `scripts/verify-local.sh` and `scripts/verify-gpu.sh`: smoke tests.

## Requirements

- Docker Engine 24+ (recommended)
- Docker Compose plugin v2+

For NVIDIA GPU execution:

- Compatible NVIDIA driver installed on the host.
- NVIDIA Container Toolkit installed and working.

Useful checks:

```bash
docker --version
docker compose version
nvidia-smi
```

## Quick Start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. In `.env`, adjust at least:

- `LOCAL_UID` and `LOCAL_GID` (use `id -u` and `id -g` to avoid root-owned generated files).
- `COMFY_*_BIND` to choose persistence locations on the host disk.
- `TORCH_CHANNEL` (`stable` or `nightly`).
- `COMFYUI_REF` (ComfyUI tag or commit).
- Optional tokens for private/gated models:
  - `HF_TOKEN`
  - `CIVITAI_TOKEN`

3. Run ComfyUI:

```bash
# No GPU (local)
./scripts/run-comfyui.sh local up

# With NVIDIA GPU
./scripts/run-comfyui.sh gpu up
```

4. Logs:

```bash
./scripts/run-comfyui.sh local logs
# or
./scripts/run-comfyui.sh gpu logs
```

Default UI: `http://localhost:8188`

## GPU Build and Run Sequence

Use this exact sequence on your GPU host, especially after dependency or Dockerfile changes:

1. Rebuild the GPU image from scratch.
This ensures new Python dependencies and image changes are applied.

```bash
./scripts/run-comfyui.sh gpu build --no-cache
```

2. Start ComfyUI with the GPU stack.
This launches the service using the GPU compose override.

```bash
./scripts/run-comfyui.sh gpu up
```

3. Follow container logs.
This is useful to confirm startup and detect runtime issues quickly.

```bash
./scripts/run-comfyui.sh gpu logs
```

## Manager and Previews

### ComfyUI-Manager

- The container installs `manager_requirements.txt` automatically when that file exists.
- Startup enables the manager by default with `--enable-manager`.
- The image installs `matrix-nio` by default (`INSTALL_MATRIX_NIO=true`) to avoid the manager warning about matrix sharing dependency.
- The image installs `opencv-python-headless` by default (`INSTALL_OPENCV_HEADLESS=true`) to cover custom nodes that require `cv2`.
- The image preinstalls Easy-Use repair dependencies by default (`INSTALL_EASYUSE_REPAIR_DEPS=true`) to avoid import-time failures in custom nodes that depend on `diffusers` internals.
- Preflight enforces manager policy defaults to allow install/download actions in remote hosts:
  - `security_level=normal`
  - `network_mode=personal_cloud`
  - Config path: `/opt/comfyui/user/__manager/config.ini`
- Image build applies write permissions for Python runtime packages to `LOCAL_UID/LOCAL_GID`, so manager-installed Python dependencies can be installed without root.
- Runtime sets `UV_LINK_MODE=copy` by default to avoid hardlink warnings in containerized filesystems.
- Preflight now validates imports for `cv2`, `diffusers`, `transformers`, and `peft`, and prints the real exception if one fails.
- Preflight also scans mounted custom nodes and installs their dependencies automatically from:
  - `requirements.txt`
  - `requirements-*.txt` / `requirements_*.txt`
  - `pyproject.toml` (`[project].dependencies`)
- To avoid reinstalling on every start, dependency manifests are hashed and cached in:
  - `/opt/comfyui/user/.cache/custom-node-deps-state.json`

### High-Quality Preview

- By default, startup uses `--preview-method auto`.
- For high-quality TAESD previews, place these files in `data/models/vae_approx`:
  - `taesd_decoder.pth`
  - `taesdxl_decoder.pth`
  - `taesd3_decoder.pth`
  - `taef1_decoder.pth`

Then restart ComfyUI and use this in `.env`:

```bash
COMFYUI_EXTRA_ARGS=--enable-manager --preview-method taesd
```

## PyTorch Channels (NVIDIA)

This repository follows the official ComfyUI recommendation:

- Stable (default):

```bash
pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130
```

- Optional nightly:

```bash
pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu132
```

Channel selection is controlled with `TORCH_CHANNEL`:

- `TORCH_CHANNEL=stable` uses `cu130`.
- `TORCH_CHANNEL=nightly` uses nightly `cu132`.

When you change channel, rebuild the image:

```bash
./scripts/run-comfyui.sh local build --no-cache
```

## Folder Structure and Commits

ComfyUI runtime directories are created automatically under `data/`.

- Folders with `.gitkeep` (tracked):
  - `data/models/audio_encoders`
  - `data/models/checkpoints`
  - `data/models/clip`
  - `data/models/clip_vision`
  - `data/models/configs`
  - `data/models/controlnet`
  - `data/models/diffusers`
  - `data/models/vae`
  - `data/models/vae_approx`
  - `data/models/embeddings`
  - `data/models/gligen`
  - `data/models/hypernetworks`
  - `data/models/latent_upscale_models`
  - `data/models/loras`
  - `data/models/model_patches`
  - `data/models/photomaker`
  - `data/models/style_models`
  - `data/models/text_encoders`
  - `data/models/unet`
  - `data/models/upscale_models`
  - `data/models/diffusion_models`
  - `data/custom_nodes`
  - `data/input`
  - `data/output`
  - `data/user`
  - `data/temp`

The model subfolders above are intentionally aligned with the current upstream tree in ComfyUI `models/`.

Any new file inside those folders is ignored by git (only `.gitkeep` is tracked).

- Workflows folders:
  - `data/workflows` (tracked and commit-ready)
  - `data/workflows/editing` (ignored from git for work-in-progress edits)

Workflow commit policy:

- Files under `data/workflows` are versioned.
- Files under `data/workflows/editing` are not included in commits.

## Workflows

Save a workflow (if no source file is provided, it uses the latest JSON from `data/user/default/workflows`):

```bash
./scripts/workflow-save.sh
```

Save directly into the editing folder:

```bash
./scripts/workflow-save.sh --editing
```

Move an existing workflow into the editing folder:

```bash
./scripts/workflow-move-to-edit.sh my_workflow.json
```

## Where Installed Files Appear

- Models:
  - `data/models/<category>` (for example `data/models/checkpoints`, `data/models/loras`, etc.)

- Custom nodes installed by ComfyUI-Manager:
  - Usually: `data/custom_nodes`
  - Depending on manager/user mode configuration, they may appear under:
    - `data/user/default/ComfyUI/custom_nodes`

- Workflows saved from the ComfyUI UI:
  - Default UI save location: `data/user/default/workflows`
  - `data/workflows` is your commit-ready workflow folder in this repository.
  - `data/workflows/editing` is your local non-commit editing area.

Single-path mapping configured in compose:

- `data/models` -> `/opt/comfyui/models`
- `data/custom_nodes` -> `/opt/comfyui/custom_nodes`
- `data/input` -> `/opt/comfyui/input`
- `data/output` -> `/opt/comfyui/output`
- `data/user` -> `/opt/comfyui/user`
- `data/temp` -> `/opt/comfyui/temp`
- `data/workflows` -> `/opt/comfyui/workflows`

No duplicate bind mounts are used.

If ComfyUI-Manager stores a node under the user directory convention, you can still find it in `data/user/...`.

## Stop ComfyUI

Use the run script with `down`:

```bash
./scripts/run-comfyui.sh gpu down
```

For local mode:

```bash
./scripts/run-comfyui.sh local down
```

Note: `Ctrl + C` only stops the live logs stream when running `./scripts/run-comfyui.sh gpu logs`. It does not stop the detached container started with `up`.

## Script to Update COMFYUI_REF

Update to the latest available tag:

```bash
./scripts/update-comfyui-ref.sh
```

Pin a specific reference:

```bash
./scripts/update-comfyui-ref.sh --ref v0.9.2 --file .env
```

## Download Models (Hugging Face and CivitAI)

Download from Hugging Face (public model):

```bash
./scripts/model-download.sh --provider huggingface --model-dir checkpoints \
  --repo Comfy-Org/stable-diffusion-v1-5-archive \
  --file v1-5-pruned-emaonly-fp16.safetensors
```

Download from Hugging Face with token (private/gated):

```bash
./scripts/model-download.sh --provider huggingface --model-dir checkpoints \
  --repo my-org/private-model-repo \
  --file model.safetensors \
  --token "$HF_TOKEN"
```

Download from CivitAI using model version ID (public):

```bash
./scripts/model-download.sh --provider civitai --model-dir loras \
  --model-id 12345 \
  --output my-lora.safetensors
```

Download from CivitAI with token:

```bash
./scripts/model-download.sh --provider civitai --model-dir checkpoints \
  --url "https://civitai.com/api/download/models/12345" \
  --token "$CIVITAI_TOKEN" \
  --output model.safetensors
```

The script supports both token and tokenless downloads. Public files can be downloaded without a token.

## Manual Compose Operation

Local usage (no GPU):

```bash
docker compose up --build -d
docker compose logs -f comfyui
```

Default UI: `http://localhost:8188`

Stop:

```bash
docker compose down
```

Usage on GPU host (Lightning):

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up --build -d
docker compose -f docker-compose.yml -f docker-compose.gpu.yml logs -f comfyui
```

Stop:

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

## Persistence (bind mounts)

By default, these host paths are mounted (configurable in `.env`):

- `./data/models` -> `/opt/comfyui/models`
- `./data/custom_nodes` -> `/opt/comfyui/custom_nodes`
- `./data/input` -> `/opt/comfyui/input`
- `./data/output` -> `/opt/comfyui/output`
- `./data/user` -> `/opt/comfyui/user`
- `./data/temp` -> `/opt/comfyui/temp`
- `./data/workflows` -> `/opt/comfyui/workflows`

## Update ComfyUI Version

1. Update the reference:

```bash
./scripts/update-comfyui-ref.sh
```

2. Rebuild:

```bash
docker compose build --no-cache comfyui
```

3. Start the stack again.

## Troubleshooting

### "Torch not compiled with CUDA enabled"

- Verify you are starting with the GPU override (`docker-compose.gpu.yml`).
- Verify the host exposes the GPU to the container runtime (`nvidia-smi` on host and inside the container when applicable).
- Rebuild if you changed channel or versions.

### Manager error: security_level/network_mode restriction

If logs show an error like:

`security_level must be normal or below, and network_mode must be set to personal_cloud`

make sure these values are set in `.env`:

```bash
COMFY_MANAGER_ENFORCE_CONFIG=true
COMFY_MANAGER_SECURITY_LEVEL=normal
COMFY_MANAGER_NETWORK_MODE=personal_cloud
```

Then rebuild and restart:

```bash
./scripts/run-comfyui.sh gpu build --no-cache
./scripts/run-comfyui.sh gpu up
```

### Manager dependency install fails with permission denied

If logs show an error like `Failed to create directory /usr/local/lib/python... site-packages ... Permission denied`, rebuild with the correct `LOCAL_UID` and `LOCAL_GID` from your host:

```bash
id -u
id -g
./scripts/run-comfyui.sh gpu build --no-cache
./scripts/run-comfyui.sh gpu up
```

This project propagates `LOCAL_UID/LOCAL_GID` to Docker build and assigns write access for runtime package installation.

### "OpenCV not installed"

The image installs OpenCV headless by default:

```bash
INSTALL_OPENCV_HEADLESS=true
```

If you still see this message, rebuild the image without cache and restart:

```bash
./scripts/run-comfyui.sh gpu build --no-cache
./scripts/run-comfyui.sh gpu up
```

### "Package diffusers installed successfully" but module load still fails

This usually means `diffusers` was present but one of its related imports failed (for example `transformers`, `peft`, or `huggingface_hub` compatibility).

This project now preinstalls a known-good dependency set for that scenario:

```bash
INSTALL_EASYUSE_REPAIR_DEPS=true
```

Then rebuild without cache and restart:

```bash
./scripts/run-comfyui.sh gpu build --no-cache
./scripts/run-comfyui.sh gpu up
```

After restart, check preflight logs. They now show the exact failing import (if any), instead of only the generic `Module 'diffusers' load failed` message.

### Custom nodes fail after container recreation

This stack auto-installs dependencies for mounted custom nodes on startup, so recreating the container does not lose Python packages required by those nodes.

Controls in `.env`:

```bash
COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS=true
COMFY_CUSTOM_NODE_DEPS_STRICT=false
COMFY_CUSTOM_NODE_DEPS_FORCE=false
```

- `COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS=true`: enables scanning/install.
- `COMFY_CUSTOM_NODE_DEPS_STRICT=true`: fail startup if any dependency install fails.
- `COMFY_CUSTOM_NODE_DEPS_FORCE=true`: force reinstall even when manifests are unchanged.

If you add or update a custom node dependency manifest, restart ComfyUI and preflight will apply the changes automatically.

### UV warning: Failed to hardlink files

This warning is usually non-fatal. It means uv could not use hardlinks (common in container/bind mount setups) and falls back to file copy.

This project defaults to:

```bash
UV_LINK_MODE=copy
```

so the warning is suppressed and behavior is explicit.

### "No username set in the environment" or "getpwuid(): uid not found"

- This happens when the container runs as a numeric UID that does not exist in `/etc/passwd`.
- The stack now sets `USER`, `LOGNAME`, `HOME`, `XDG_CACHE_HOME`, and `TORCHINDUCTOR_CACHE_DIR` explicitly.
- Make sure your `.env` includes `COMFY_RUNTIME_USER` (default: `comfyui`) and restart the stack.

```bash
./scripts/run-comfyui.sh gpu restart
```

### Permission Issues in Mounted Folders

- Adjust `LOCAL_UID` and `LOCAL_GID` in `.env` to match the real host user values.

### ComfyUI Starts but Does Not Generate Images

- Make sure you have models in `/opt/comfyui/models/checkpoints` (bind mount `COMFY_MODELS_BIND`).

## Notes

- For local development without GPU, keep `COMFY_PRECHECK_CUDA=false`.
- To force CUDA validation at startup on a GPU host, set `COMFY_PRECHECK_CUDA=true`.
