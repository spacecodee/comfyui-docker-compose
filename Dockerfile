FROM python:3.13-slim-bookworm

ARG COMFYUI_REF=v0.9.2
ARG TORCH_CHANNEL=stable
ARG INSTALL_MATRIX_NIO=true
ARG INSTALL_OPENCV_HEADLESS=true
ARG INSTALL_EASYUSE_REPAIR_DEPS=true
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000

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
    fi \
    && if [ "${INSTALL_MATRIX_NIO}" = "true" ]; then \
      python -m pip install matrix-nio; \
    else \
      echo "INSTALL_MATRIX_NIO=false, skipping matrix-nio install"; \
    fi \
    && if [ "${INSTALL_OPENCV_HEADLESS}" = "true" ]; then \
      python -m pip install opencv-python-headless; \
    else \
      echo "INSTALL_OPENCV_HEADLESS=false, skipping opencv-python-headless install"; \
    fi \
    && if [ "${INSTALL_EASYUSE_REPAIR_DEPS}" = "true" ]; then \
      python -m pip install --upgrade \
        "numpy>=1.19.0" \
        "diffusers>=0.32.2" \
        "huggingface_hub>=0.25.0" \
        "transformers>=4.48.0" \
        "peft>=0.14.0" \
        "protobuf>=4.25.3" \
        accelerate; \
    else \
      echo "INSTALL_EASYUSE_REPAIR_DEPS=false, skipping Easy-Use repair dependency preinstall"; \
    fi \
    && chown -R "${LOCAL_UID}:${LOCAL_GID}" /usr/local/lib/python3.13/site-packages /usr/local/bin /usr/local/share \
    && chmod -R u+rwX /usr/local/lib/python3.13/site-packages /usr/local/bin /usr/local/share

COPY scripts/preflight.sh /usr/local/bin/preflight.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/preflight.sh /usr/local/bin/entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
