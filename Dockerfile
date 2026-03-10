# syntax=docker/dockerfile:1
# ComfyUI Docker Image with Blackwell NVFP4 Support
# Optimized for NVIDIA Blackwell GPUs (RTX 50 series)
# Supports: image, video, and audio generation workflows

# Build arguments for version pinning --Global Scope--
ARG CUDA_BASE_IMAGE=nvidia/cuda:13.1.1-devel-ubuntu24.04
ARG TORCH_WHEEL_URL=https://download.pytorch.org/whl/cu130/torch-2.10.0%2Bcu130-cp312-cp312-manylinux_2_28_x86_64.whl
ARG TORCHVISION_WHEEL_URL=https://download.pytorch.org/whl/cu130/torchvision-0.25.0%2Bcu130-cp312-cp312-manylinux_2_28_x86_64.whl
ARG TORCHAUDIO_WHEEL_URL=https://download.pytorch.org/whl/cu130/torchaudio-2.10.0%2Bcu130-cp312-cp312-manylinux_2_28_x86_64.whl
ARG COMFYUI_BRANCH=master
ARG SAGEATTENTION_VERSION=v2
ARG SAGEATTENTION_USE=1
ARG TORCH_CUDA_ARCH_LIST=12.0

FROM ${CUDA_BASE_IMAGE}

# Re-declare ARGs so they are available inside this build stage.
# Every ARG defined before FROM must be re-declared here to be usable.
ARG SAGEATTENTION_VERSION
ARG SAGEATTENTION_USE
ARG TORCH_WHEEL_URL
ARG TORCHVISION_WHEEL_URL
ARG TORCHAUDIO_WHEEL_URL
ARG COMFYUI_BRANCH
ARG TORCH_CUDA_ARCH_LIST

# Bake runtime-needed values into the image environment
ENV SAGEATTENTION_VERSION=${SAGEATTENTION_VERSION}
ENV SAGEATTENTION_USE=${SAGEATTENTION_USE}
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}

# Setup environment for non-interactive installs
ENV DEBIAN_FRONTEND=noninteractive
# Allow pip to install into the system Python (we're in a container, it's fine)
ENV PIP_BREAK_SYSTEM_PACKAGES=1
# PIP_IGNORE_INSTALLED=1 forces pip to install our exact wheel versions even if
# the base CUDA image has pre-installed conflicting package versions.
# NOTE: startup.sh explicitly unsets this at runtime so node requirements are
# installed efficiently (skip already-satisfied packages instead of reinstalling).
ENV PIP_IGNORE_INSTALLED=1
ENV PIP_NO_CACHE_DIR=1

# Install system dependencies
#
# Core:
#   python3, python3-pip, python3-dev, git: runtime and build tools
#
# Image support:
#   libgl1, libglib2.0-0: required by OpenCV (used by many custom nodes)
#   libsm6, libxext6, libxrender1: full OpenCV headless video frame support
#
# Video support:
#   ffmpeg: encode/decode video for AnimateDiff, HunyuanVideo, Wan, CogVideoX, etc.
#
# Audio support:
#   libsndfile1: required by the soundfile/PySoundFile Python library and torchaudio
#   sox: audio format conversion used by some audio generation nodes
#
# Utilities (used by custom node installers and ComfyUI Manager):
#   wget, curl: HTTP downloads in node install scripts
#   aria2: parallel download manager used by ComfyUI Manager for models
#   unzip, p7zip-full: archive extraction in node installers
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    libsndfile1 \
    sox \
    wget \
    curl \
    aria2 \
    unzip \
    p7zip-full \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip to latest version
RUN python3 -m pip install --upgrade pip

# Set working directory
WORKDIR /app

# Clone ComfyUI repository
RUN git clone --branch ${COMFYUI_BRANCH} https://github.com/Comfy-Org/ComfyUI.git .

# Install PyTorch with CUDA 13.0 support.
# These specific wheels are critical for Blackwell GPU support.
# Cache mount avoids re-downloading on rebuilds when the URL hasn't changed.
RUN --mount=type=cache,target=/root/.cache/pip \
    PIP_NO_CACHE_DIR=0 pip install \
    "${TORCH_WHEEL_URL}" \
    "${TORCHVISION_WHEEL_URL}" \
    "${TORCHAUDIO_WHEEL_URL}"

# Write a pip constraints file that locks PyTorch to exactly the versions
# installed above. This prevents custom nodes from accidentally overriding them.
RUN echo "torch @ ${TORCH_WHEEL_URL}" > /app/constraints.txt && \
    echo "torchvision @ ${TORCHVISION_WHEEL_URL}" >> /app/constraints.txt && \
    echo "torchaudio @ ${TORCHAUDIO_WHEEL_URL}" >> /app/constraints.txt

# Install SageAttention for improved attention mechanism performance.
# Triton is required for SageAttention's CUDA kernels.
# v2: stable, works for all image and most video models
# v3: supports NVFP4 natively, best for Blackwell — try at own risk on Python 3.12
RUN if [ "$SAGEATTENTION_VERSION" != "none" ]; then \
      pip install triton -c /app/constraints.txt && \
      git clone https://github.com/thu-ml/SageAttention.git /app/tmp/sageattention && \
      if [ "$SAGEATTENTION_VERSION" = "v3" ]; then \
        cd /app/tmp/sageattention/sageattention3_blackwell; \
      elif [ "$SAGEATTENTION_VERSION" = "v2" ]; then \
        cd /app/tmp/sageattention; \
      else \
        echo "ERROR: SAGEATTENTION_VERSION must be v2, v3, or none" && exit 1; \
      fi && \
      pip install --no-build-isolation -c /app/constraints.txt . && \
      cd /app && \
      rm -rf /app/tmp/sageattention; \
    fi

# Install flash-attn for faster attention inference.
# Requires --no-build-isolation so it can detect the installed PyTorch/CUDA.
# Compilation takes several minutes but only runs at image build time.
RUN pip install flash-attn --no-build-isolation -c /app/constraints.txt

# Install base ComfyUI requirements
RUN pip install -r requirements.txt -c /app/constraints.txt

# Install additional wheels from wheels.txt (e.g. Nunchaku for NVFP4 support).
# Comment out lines in wheels.txt to skip individual packages.
RUN --mount=type=bind,source=.,target=/mnt/context,ro \
    if [ -f "/mnt/context/wheels.txt" ]; then \
        echo "Found wheels.txt, installing wheels..."; \
        while IFS= read -r wheel_url || [ -n "$wheel_url" ]; do \
            case "$wheel_url" in \
                \#*|"") continue ;; \
            esac; \
            echo "Installing: $wheel_url"; \
            pip install "$wheel_url" -c /app/constraints.txt || true; \
        done < /mnt/context/wheels.txt; \
    else \
        echo "No wheels.txt found, skipping additional wheels..."; \
    fi

# Pre-install dependencies from any custom nodes already present in the build
# context. This is an optimisation for pre-baked images — new nodes added at
# runtime via ComfyUI Manager are handled by startup.sh on container restart.
RUN --mount=type=bind,source=.,target=/mnt/context,ro \
    if [ -d "/mnt/context/custom_nodes" ]; then \
        echo "Pre-installing custom node dependencies from build context..."; \
        find /mnt/context/custom_nodes -maxdepth 2 -name "requirements.txt" \
        -exec pip install -r {} -c /app/constraints.txt \; || true; \
    fi

# Clone default custom nodes into a staging directory that is NOT the volume
# mount point. startup.sh copies them into /app/custom_nodes at runtime so
# they are visible even when the host volume overlays /app/custom_nodes.
RUN mkdir -p /app/default_custom_nodes && \
    git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git       /app/default_custom_nodes/ComfyUI-Manager && \
    git clone --depth 1 https://github.com/flybirdxx/ComfyUI-Qwen-TTS.git      /app/default_custom_nodes/ComfyUI-Qwen-TTS && \
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git             /app/default_custom_nodes/ComfyUI-GGUF && \
    git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git     /app/default_custom_nodes/ComfyUI-LTXVideo

# Pre-install dependencies for the bundled custom nodes at build time so they
# are available in the image layers (avoids re-downloading on every startup).
RUN for req in /app/default_custom_nodes/*/requirements.txt; do \
        [ -f "$req" ] || continue; \
        pip install -r "$req" -c /app/constraints.txt || true; \
    done

# ComfyUI-Qwen-TTS requires transformers>=4.52.0 for check_model_inputs.
# Force-upgrade here so the pinned PyTorch versions are still respected.
RUN pip install "transformers>=4.52.0" -c /app/constraints.txt

# Copy the startup script. Keeping it as a separate file avoids heredoc
# quoting issues and makes it easy to read and lint independently.
COPY startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Image metadata
LABEL org.opencontainers.image.title="ComfyUI Blackwell NVFP4" \
      org.opencontainers.image.description="ComfyUI with NVIDIA Blackwell NVFP4 support for RTX 50 series GPUs" \
      org.opencontainers.image.source="https://github.com/loukaniko85/comfyui-blackwell-docker"

# Expose ComfyUI web interface port
EXPOSE 8188

# Health check — verifies ComfyUI's HTTP server is responding.
# start-period accounts for startup.sh installing custom node requirements.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1

# startup.sh handles: node requirements install, install.py scripts, SageAttention flag
ENTRYPOINT ["/app/startup.sh"]

# Default command — startup.sh appends --use-sage-attention when SAGEATTENTION_USE=1
CMD ["python3", "main.py", "--listen", "0.0.0.0"]
