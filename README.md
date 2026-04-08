# comfyui-local-workspace

This repository has been simplified to run ComfyUI locally.
It no longer uses Docker or Docker Compose.

The dedicated synced directories are:

- data/workflows
- data/input
- data/output

This keeps your workflows and I/O inside your project folder.
Everything else (models, custom nodes, etc.) lives directly in ./comfyui.

## What is included now

- scripts/setup-local.sh: clones/updates ComfyUI into ./comfyui, prepares Python dependencies (venv or existing env), and links workflows/input/output.
- scripts/run-comfyui.sh: commands for setup, local start, custom node deps, preview setup, and model downloads.
- scripts/install-custom-node-deps.sh: installs custom node dependencies from requirements*.txt or pyproject.toml.
- scripts/prepare-data-dirs.sh: ensures data/workflows, data/workflows/editing, data/input, and data/output.
- scripts/setup-preview-method.sh: downloads TAESD decoders for --preview-method (automatic or manual).
- scripts/model-download.sh: downloads models from Hugging Face or CivitAI into ComfyUI model folders.
- scripts/workflow-save.sh: copies workflows into the versioned directory.
- scripts/workflow-move-to-edit.sh: moves workflows into editing (git-ignored).
- .env.example: minimal local-mode configuration.

## Structure

```text
.
├── data/
│   ├── input/
│   │   └── .gitkeep
│   ├── output/
│   │   └── .gitkeep
│   └── workflows/
│       ├── .gitkeep
│       └── editing/
│           └── .gitkeep
└── scripts/
```

## Requirements

- Git
- Python 3.13 recommended
- python3-venv installed

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y git python3 python3-venv
```

## Python and PyTorch Version Guidance

Python:

- Python 3.14 works, but some custom nodes may have issues.
- Free-threaded Python works, but some dependencies re-enable the GIL, so it is not fully supported.
- Python 3.13 is very well supported (recommended default).
- If you hit custom node dependency problems on 3.13, try Python 3.12.
- In managed environments that block virtualenv creation (for example some Studio/conda setups), set COMFY_USE_VENV=false.

PyTorch:

- Torch 2.4+ is supported.
- Some features and optimizations may work better only on newer versions.
- Recommended: latest major PyTorch version with the latest CUDA version, unless that release is less than two weeks old.

Tip: set COMFY_PYTHON_BIN in .env (for example python3.13) to control which Python version is used.
Tip: if you get "Venv creation is not allowed", set COMFY_USE_VENV=false.

## Quick Start

1. Create your local env file:

```bash
cp .env.example .env
```

2. Download/update ComfyUI and prepare the environment:

```bash
./scripts/run-comfyui.sh setup
```

3. Start ComfyUI:

```bash
./scripts/run-comfyui.sh start
```

4. Open in browser:

```text
http://127.0.0.1:8188
```

For remote environments (Cloudspaces/Studio/Codespaces), use the forwarded/public URL for port 8188.
If you get HTTP 403, it is usually platform authorization/port-sharing policy, not a ComfyUI crash.

## Workflows, Input, and Output Linking

During setup and start, these links are created:

```text
comfyui/user/default/workflows -> data/workflows
comfyui/input -> data/input
comfyui/output -> data/output
```

This means uploads in Input and generated files in Output remain in your project folder.

data/workflows/editing is kept for work-in-progress files and is ignored by git.

By default, data/input and data/output keep only .gitkeep in git, while runtime files are ignored.

## Custom Nodes

In local mode, install custom nodes into:

```text
comfyui/custom_nodes
```

Dependencies can be installed with:

```bash
./scripts/run-comfyui.sh deps
```

And during start they are installed automatically if COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS=true.

## Dependency Auto-Sync and Repair

On start, the runner can automatically:

- sync ComfyUI core requirements when requirements.txt changes
- install manager requirements when --enable-manager is active
- install matrix-nio when --enable-manager is active (to avoid matrix sharing warning)
- repair requests stack when RequestsDependencyWarning is detected
- repair NumPy/SciPy ABI mismatches (for example NumPy 2.x with SciPy built for NumPy 1.x)
- optionally upgrade torch/torchvision/torchaudio to cu130 wheels when torch cuda < 13
- repair torchaudio when it is incompatible with the installed torch build

This behavior is controlled by:

- COMFY_AUTO_SYNC_REQUIREMENTS
- COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS
- COMFY_AUTO_INSTALL_MATRIX_NIO
- COMFY_AUTO_FIX_REQUESTS_STACK
- COMFY_AUTO_FIX_NUMPY_SCIPY_COMPAT
- COMFY_AUTO_FIX_TORCH_CUDA130
- COMFY_AUTO_FIX_TORCH_CUDA130_FORCE
- COMFY_AUTO_FIX_TORCHAUDIO

If you still see this warning:

- WARNING: You need pytorch with cu130 or higher to use optimized CUDA operations.

COMFY_AUTO_FIX_TORCH_CUDA130 is enabled by default. If needed, keep it true and run start once.
Set it to false only if you explicitly want to skip torch/cu130 auto-upgrade.

## Model Downloads (Hugging Face / CivitAI)

You can download models directly into ComfyUI model directories (checkpoints, loras, vae, etc.):

```bash
./scripts/model-download.sh --provider huggingface --model-dir checkpoints \
	--repo Comfy-Org/stable-diffusion-v1-5-archive \
	--file v1-5-pruned-emaonly-fp16.safetensors

./scripts/model-download.sh --provider civitai --model-dir loras \
	--model-id 12345 --output my_lora.safetensors
```

You can also run it through the wrapper script:

```bash
./scripts/run-comfyui.sh model-download --provider civitai --model-dir checkpoints --model-id 12345
```

Destination root:

- COMFY_MODELS_DIR if set
- otherwise: <COMFYUI_DIR>/models

The allowed model subdirectories are listed in scripts/comfy-model-dirs.txt.

## Environment Variables

Configure .env as needed:

- COMFYUI_REPO_URL: ComfyUI repository URL (official repo by default).
- COMFYUI_REF: branch/tag/commit to use.
- COMFYUI_DIR: local ComfyUI directory (./comfyui).
- COMFY_USE_VENV: true/false toggle for creating and using .venv.
- COMFY_PYTHON_BIN: Python binary used by setup/start/deps (python3.13 recommended).
- COMFY_VENV_DIR: local virtual environment directory (./.venv).
- COMFY_WORKFLOWS_DIR: versioned workflows directory (./data/workflows).
- COMFY_INPUT_DIR: synced input directory (./data/input).
- COMFY_OUTPUT_DIR: synced output directory (./data/output).
- COMFY_MODELS_DIR: optional models root override (defaults to <COMFYUI_DIR>/models).
- COMFYUI_HOST: web host binding.
- COMFYUI_PORT: web port.
- COMFY_AUTO_PUBLIC_BIND: auto-switch localhost host values to 0.0.0.0 in remote workspaces.
- COMFYUI_PREVIEW_METHOD: auto, taesd, latent2rgb, or none.
- COMFYUI_EXTRA_ARGS: extra arguments passed to main.py.
- COMFY_PREVIEW_AUTO_SETUP: download preview decoders during local setup.
- COMFY_PREVIEW_MODELS_BASE_URL: download source for TAESD decoders.
- COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS: install custom node dependencies on start.
- COMFY_CUSTOM_NODE_DEPS_STRICT: fail if any dependency install fails.
- COMFY_CUSTOM_NODE_DEPS_FORCE: reinstall dependencies even when unchanged.
- COMFY_AUTO_SYNC_REQUIREMENTS: auto-install core requirements when requirements.txt changes.
- COMFY_AUTO_INSTALL_MANAGER_REQUIREMENTS: auto-install manager requirements when --enable-manager is used.
- COMFY_AUTO_INSTALL_MATRIX_NIO: install matrix-nio automatically for ComfyUI-Manager matrix sharing.
- COMFY_AUTO_FIX_REQUESTS_STACK: repair requests/urllib3/chardet/charset-normalizer mismatch warning (caps urllib3 at <=2.5.0 for lightning-sdk compatibility).
- COMFY_AUTO_FIX_NUMPY_SCIPY_COMPAT: repair NumPy/SciPy incompatibility and pin NumPy to <2 when needed.
- COMFY_AUTO_FIX_TORCH_CUDA130: attempt torch/torchvision/torchaudio upgrade to cu130 when needed.
- COMFY_AUTO_FIX_TORCH_CUDA130_FORCE: re-attempt cu130 upgrade even after a previous failed attempt.
- COMFY_AUTO_FIX_TORCHAUDIO: attempt torchaudio repair when torch/torchaudio are mismatched.
- HF_TOKEN: optional Hugging Face token used by model-download.sh.
- CIVITAI_TOKEN: optional CivitAI token used by model-download.sh.

Default branch in this repo config is COMFYUI_REF=master.

## Remote Access Notes (403 Forbidden)

If your browser shows HTTP 403 on a forwarded URL, check:

- COMFYUI is listening on 0.0.0.0 (set COMFYUI_HOST=0.0.0.0).
- Port 8188 is shared/forwarded in your platform panel.
- Your browser session is authorized for that workspace URL.

This repo sets COMFYUI_HOST=0.0.0.0 and COMFY_AUTO_PUBLIC_BIND=true by default for remote compatibility.

## Preview Method (Automatic and Manual Download)

If .env uses COMFYUI_PREVIEW_METHOD=taesd (or auto), you can download TAESD decoders:

- automatically during setup when COMFY_PREVIEW_AUTO_SETUP=true
- manually with the preview setup script

Manual commands:

```bash
./scripts/setup-preview-method.sh
./scripts/setup-preview-method.sh --method taesd
./scripts/setup-preview-method.sh --method taesd --force
```

The script downloads:

- taesd_decoder.pth
- taesdxl_decoder.pth
- taesd3_decoder.pth
- taef1_decoder.pth

Destination:

```text
comfyui/models/vae_approx
```

## Available Scripts

```bash
# Initial setup / update ComfyUI
./scripts/run-comfyui.sh setup

# Start ComfyUI locally
./scripts/run-comfyui.sh start

# Start with extra args (example)
./scripts/run-comfyui.sh start -- --disable-auto-launch

# Manually install custom node dependencies
./scripts/run-comfyui.sh deps

# Manually download preview decoders
./scripts/run-comfyui.sh preview
./scripts/run-comfyui.sh preview --method taesd --force

# Download models (Hugging Face / CivitAI)
./scripts/model-download.sh --provider huggingface --model-dir checkpoints --repo owner/repo --file model.safetensors
./scripts/model-download.sh --provider civitai --model-dir loras --model-id 12345
./scripts/run-comfyui.sh model-download --provider civitai --model-dir checkpoints --model-id 12345

# Save a workflow to the main workflows directory
./scripts/workflow-save.sh my_workflow.json

# Save directly to editing
./scripts/workflow-save.sh --editing my_workflow.json

# Move an existing workflow to editing
./scripts/workflow-move-to-edit.sh my_workflow.json
```

## Migration from the Previous Docker Workflow

Removed from this repository:

- docker-compose.yml
- docker-compose.gpu.yml
- Dockerfile
- entrypoint, preflight, verify-*, and compose helper scripts

The current workflow is fully local to simplify custom node installation and maintenance.