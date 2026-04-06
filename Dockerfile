FROM python:3.13-slim-bookworm

ARG COMFYUI_REF=v0.9.2
ARG TORCH_CHANNEL=stable

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    COMFYUI_PATH=/opt/comfyui

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    tini \
    && rm -rf /var/lib/apt/lists/* \
    && git clone https://github.com/Comfy-Org/ComfyUI.git "${COMFYUI_PATH}" \
    && cd "${COMFYUI_PATH}" \
    && git fetch --tags --force \
    && git checkout "${COMFYUI_REF}"

WORKDIR ${COMFYUI_PATH}

RUN python -m pip install --upgrade pip setuptools wheel \
        && if [ "${TORCH_CHANNEL}" = "nightly" ]; then \
      python -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu132; \
    else \
      python -m pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130; \
        fi \
        && python -m pip install -r requirements.txt \
        && if [ -f manager_requirements.txt ]; then \
            python -m pip install -r manager_requirements.txt; \
        else \
            echo "manager_requirements.txt not found, skipping manager dependency install"; \
        fi

COPY scripts/preflight.sh /usr/local/bin/preflight.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/preflight.sh /usr/local/bin/entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
