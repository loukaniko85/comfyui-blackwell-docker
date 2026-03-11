#!/bin/bash
set -e

# Protect PyTorch versions from being changed by node installs
export PIP_CONSTRAINT=/app/constraints.txt

# ---------------------------------------------------------------------------
# Seed default custom nodes into the (volume-mounted) /app/custom_nodes dir.
# Nodes are cloned into /app/default_custom_nodes at build time so they
# survive the volume mount that overlays /app/custom_nodes at runtime.
# We only copy a node if it is not already present (preserves user updates).
# ---------------------------------------------------------------------------
if [ -d "/app/default_custom_nodes" ]; then
    mkdir -p /app/custom_nodes
    for src in /app/default_custom_nodes/*/; do
        node_name=$(basename "$src")
        dest="/app/custom_nodes/${node_name}"
        if [ ! -d "$dest" ]; then
            echo "Seeding default node: ${node_name}"
            cp -r "$src" "$dest"
        fi
    done
fi

# Unset PIP_IGNORE_INSTALLED so we don't wastefully reinstall already-installed
# packages on every startup. That flag is only needed at image build time to
# ensure exact wheel versions get installed over any base-image pre-installs.
unset PIP_IGNORE_INSTALLED

# ---------------------------------------------------------------------------
# Install Python dependencies for all custom nodes.
# This runs on every startup, so nodes installed via ComfyUI Manager only
# need a container restart — not a full image rebuild.
# ---------------------------------------------------------------------------
if [ -d "/app/custom_nodes" ]; then
    for req in /app/custom_nodes/*/requirements.txt; do
        [ -f "$req" ] || continue
        node_name=$(basename "$(dirname "$req")")
        echo "Installing requirements for ${node_name}..."
        pip install -r "$req" -c /app/constraints.txt --quiet || true
    done
fi

# ---------------------------------------------------------------------------
# Download VibeVoice models on first run if not already present.
# huggingface_hub is available because it is a VibeVoice requirement installed
# at build time. Set VIBEVOICE_MODEL=none to skip the download entirely.
# Options: VibeVoice-1.5B (5.4GB), VibeVoice-Large (18.7GB),
#          VibeVoice-Large-Q8 (11.6GB), VibeVoice-Large-Q4 (6.6GB)
# ---------------------------------------------------------------------------
VIBEVOICE_MODEL="${VIBEVOICE_MODEL:-VibeVoice-1.5B}"
VIBEVOICE_DIR="/app/models/vibevoice"

if [ "${VIBEVOICE_MODEL}" != "none" ]; then
    case "${VIBEVOICE_MODEL}" in
        VibeVoice-1.5B)     HF_REPO="microsoft/VibeVoice-1.5B" ;;
        VibeVoice-Large)    HF_REPO="aoi-ot/VibeVoice-Large" ;;
        VibeVoice-Large-Q8) HF_REPO="FabioSarracino/VibeVoice-Large-Q8" ;;
        VibeVoice-Large-Q4) HF_REPO="DevParker/VibeVoice7b-low-vram" ;;
        *)
            echo "Unknown VIBEVOICE_MODEL '${VIBEVOICE_MODEL}', skipping download."
            HF_REPO=""
            ;;
    esac

    # Download tokenizer files if not already present
    TOKENIZER_DIR="${VIBEVOICE_DIR}/tokenizer"
    if [ ! -f "${TOKENIZER_DIR}/tokenizer.json" ]; then
        echo "Downloading VibeVoice tokenizer (Qwen/Qwen2.5-1.5B)..."
        mkdir -p "${TOKENIZER_DIR}"
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='Qwen/Qwen2.5-1.5B', local_dir='${TOKENIZER_DIR}', allow_patterns=['tokenizer*.json', 'vocab.json', 'merges.txt'])" \
            || echo "Warning: VibeVoice tokenizer download failed"
    fi

    # Download the selected model if its directory does not yet exist
    if [ -n "${HF_REPO}" ] && [ ! -d "${VIBEVOICE_DIR}/${VIBEVOICE_MODEL}" ]; then
        echo "Downloading VibeVoice model: ${VIBEVOICE_MODEL} (${HF_REPO})..."
        mkdir -p "${VIBEVOICE_DIR}/${VIBEVOICE_MODEL}"
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='${HF_REPO}', local_dir='${VIBEVOICE_DIR}/${VIBEVOICE_MODEL}')" \
            || echo "Warning: VibeVoice model download failed"
    fi
fi

# ---------------------------------------------------------------------------
# Run install.py for nodes that need post-install setup
# ---------------------------------------------------------------------------
if [ -d "/app/custom_nodes" ]; then
    for dir in /app/custom_nodes/*/; do
        if [ -f "${dir}install.py" ]; then
            echo "Running install script for $(basename "${dir}")..."
            cd "${dir}" && python3 install.py || true
            cd /app
        fi
    done
fi

# ---------------------------------------------------------------------------
# Conditionally enable SageAttention globally.
# SAGEATTENTION_USE=0 lets you keep the library installed but only activate
# it per-model using a "Patch Sage Attention" node in your workflow.
# ---------------------------------------------------------------------------
SAGE_FLAG=""
if [ "${SAGEATTENTION_USE}" != "0" ] && [ "${SAGEATTENTION_VERSION}" != "none" ]; then
    SAGE_FLAG="--use-sage-attention"
fi

echo "Starting ComfyUI..."
exec "$@" ${SAGE_FLAG}
