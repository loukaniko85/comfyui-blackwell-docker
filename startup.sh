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
