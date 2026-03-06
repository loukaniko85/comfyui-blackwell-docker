# ComfyUI Docker with NVIDIA Blackwell NVFP4 Support

A production-ready Docker setup for ComfyUI that unlocks the full potential of NVIDIA Blackwell GPUs (RTX 50 series) through 4-bit quantization with NVFP4.

## What This Does

This Docker setup gives you:

- **🚀 3x faster generation** vs standard 16-bit models
- **💾 3.5x less VRAM usage** - Run FLUX.1-dev on 16GB GPUs
- **🔒 Sandboxed environment** - ComfyUI runs in a container, your system stays clean
- **💪 Blackwell optimization** - Native NVFP4 support for RTX 50 series GPUs
- **📦 Persistent data** - Models, outputs, custom nodes, and workflows stay on your host machine
- **🎨 Images, video, and audio** - Full support for image, video, and audio generation workflows
- **🔌 Custom nodes just work** - Install via ComfyUI Manager, restart container — no image rebuild needed

### Comparison

Comfy-Org/ComfyUI is the raw application. To use it on a Blackwell GPU you'd have to manually:

- Figure out that PyTorch doesn't ship a standard pip wheel for CUDA 13.x and hunt down the correct wheel URLs
- Compile SageAttention from source against the right CUDA/PyTorch combo
- Find, download, and configure Nunchaku for NVFP4
- Manage Python environment isolation yourself
- Set up VRAM management flags
- Handle model/output directory structure
- 
loukaniko85/comfyui-blackwell-docker handles all of that. Specifically what it adds:
**Blackwell CUDA 13.x PyTorch**	The official repo gives no guidance on this — wrong wheels break entirely
**SageAttention pre-compiled**	Compiled from source against your exact CUDA+PyTorch at build time; not installable via plain pip on Blackwell
**Nunchaku / NVFP4 engine**	Wired in via wheels.txt with correct version matching
**System isolation**	Your host Python/CUDA environment is untouched
**One-command startup**	docker-compose up -d vs a multi-step manual setup
**Persistent volumes**	Models, outputs, nodes, workflows properly separated from the container
**Custom node auto-deps**	startup.sh installs node requirements on restart — no manual pip work
**Health monitoring**	Docker restarts the container automatically if ComfyUI crashes
**Reproducible builds**	Pinned versions mean the same image builds consistently across machines

## Why NVFP4 Matters

NVIDIA's Blackwell architecture introduces NVFP4, a 4-bit floating-point format that maintains quality while dramatically reducing memory usage and increasing speed. This isn't typical lossy compression — it's a hardware-accelerated precision format designed specifically for AI workloads.

**Real-world results:**
- FLUX.1-dev: ~12 seconds on RTX 5090 (vs 40+ seconds in BF16)
- Memory: 6.77GB model size (vs 24GB in BF16)
- Quality: Virtually identical to full precision

## Requirements

### Hardware
- **NVIDIA GPU**: Blackwell architecture (RTX 50 series) recommended
  - RTX 5090, 5080, 5070 Ti, 5070, 5060 Ti, etc.
  - Also works on Ampere (RTX 30xx) and Ada (RTX 40xx) but without NVFP4 acceleration
- **VRAM**: 16GB minimum, 24GB+ recommended
- **Storage**: 100GB+ free (AI models are large)
- **RAM**: 16GB minimum

### Software
- **Docker**: Version 20.10 or newer ([Install Docker](https://docs.docker.com/engine/install/))
- **Docker Compose**: Version 2.0 or newer (usually included with Docker)
- **NVIDIA Container Toolkit**: Required for GPU support ([Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html))
- **NVIDIA Driver**: 560.x or newer (use the latest available for best compatibility)

## Quick Start

### 1. Clone this repository

```bash
git clone https://github.com/loukaniko85/comfyui-blackwell-docker.git
cd comfyui-blackwell-docker
```

### 2. Create directory structure

```bash
mkdir -p models output input custom_nodes user
```

### 3. Configure your setup

```bash
cp .env.example .env
# Edit .env with your preferred settings (optional - defaults work fine)
```

### 4. Build the image

```bash
docker-compose build
```

First build takes 15-30 minutes (compiling SageAttention from source). Grab a coffee ☕

### 5. Start ComfyUI

```bash
docker-compose up -d
```

### 6. Access the interface

Open your browser and go to:
```
http://localhost:8188
```

## Directory Structure

After setup, your folder should look like this:

```
comfyui-blackwell-docker/
├── docker-compose.yml       # Container configuration
├── Dockerfile               # Image build instructions
├── startup.sh               # Container entrypoint script
├── .env                     # Your custom settings (create from .env.example)
├── .env.example             # Template configuration with docs
├── wheels.txt               # Extra Python packages (Nunchaku wheel)
├── models/                  # AI models (checkpoints, VAEs, LoRAs, etc.)
├── output/                  # Generated images, videos, and audio
├── input/                   # Place input files for img2img/video workflows
├── custom_nodes/            # ComfyUI custom nodes
└── user/                    # Workflows and settings
```

## Installing Custom Nodes

Custom nodes work like a normal ComfyUI installation — **no image rebuild required**.

### The Process

1. **Install via ComfyUI Manager** (as usual)
   - Open ComfyUI in your browser
   - Use ComfyUI Manager to install nodes
   - The node code downloads to `./custom_nodes/`

2. **Restart the container** (that's it!)
   ```bash
   docker-compose restart comfyui
   ```

### Why Just a Restart?

On every startup, `startup.sh` automatically:
1. Scans all `custom_nodes/*/requirements.txt` files
2. Installs any missing Python dependencies (PyTorch version is always protected)
3. Runs `install.py` for nodes that need post-install setup

### Adding Multiple Nodes

Install as many nodes as you want via Manager, then restart once:
```bash
# Install node 1, node 2, node 3 via Manager
docker-compose restart comfyui
# All requirements are installed automatically on startup
```

> **When you DO need a full rebuild:** version changes in `.env` (CUDA, PyTorch, SageAttention), changes to `wheels.txt`, or modifications to the `Dockerfile`.

## Supported Workflows

### Images
- FLUX.1-dev / FLUX.1-schnell / FLUX.2-klein (NVFP4, FP8, BF16)
- Stable Diffusion 1.5, 2.1, XL, 3, 3.5
- HiDream, Chroma, and all ComfyUI-compatible image models

### Video
- **HunyuanVideo** — state-of-the-art open video generation
- **Wan 2.1** — high quality text-to-video and image-to-video
- **AnimateDiff** — animate Stable Diffusion models
- **CogVideoX** — video generation from Tsinghua
- **LTX-Video** — fast high-quality video generation
- **Mochi** — high-fidelity video generation

### Audio
- Audio generation nodes (ACE-Step, CosyVoice, AudioCraft, etc.)
- System dependencies for `torchaudio`, `soundfile`, `librosa` are pre-installed

## Using NVFP4 Models

To get maximum performance, use 4-bit quantized models:

### Where to Get NVFP4 Models

1. **FLUX Models** - [Nunchaku FLUX on HuggingFace](https://huggingface.co/mit-han-lab)
   - Download quantized FLUX.1-dev (6.77GB vs 24GB)
   - Place in `models/diffusion_models/`
   - Black Forest Labs also have [official NVFP4 models](https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-nvfp4)

2. **Other Models** - Check [Nunchaku documentation](https://nunchaku.tech/docs/)

### Using Standard Models

Regular BF16/FP16 models still work — you just won't get the NVFP4 speed boost. The setup is fully compatible with all standard ComfyUI models.

### A Note on Text Encoders and NVFP4

NVFP4 text encoder (CLIP/T5) models currently have shape issues with ComfyUI's CLIP loader. Use FP8 or FP16 text encoders alongside your NVFP4 diffusion model for now. This may be resolved in a future ComfyUI update.

## Configuration Guide

The `.env` file controls everything. The `.env.example` file has detailed documentation for every setting.

### GPU Architecture (`TORCH_CUDA_ARCH_LIST`)

```env
TORCH_CUDA_ARCH_LIST=12.0   # RTX 50 series (Blackwell)
TORCH_CUDA_ARCH_LIST=8.9    # RTX 40 series (Ada)
TORCH_CUDA_ARCH_LIST=8.6    # RTX 30 series (Ampere)
TORCH_CUDA_ARCH_LIST=7.5    # RTX 20 series (Turing)
```

### GPU Memory Management

```env
RESERVE_VRAM=1.5           # Leave 1.5GB for system (adjust per your GPU)
COMFYUI_ARGS=--lowvram --async-offload  # Memory optimization flags
```

For 24GB+ cards, remove `--lowvram` for a speed boost:
```env
COMFYUI_ARGS=--async-offload
```

### SageAttention

Controls the attention optimization library. Set in `.env`, then rebuild.

```env
SAGEATTENTION_VERSION=v2   # Stable, works for all image and most video models
SAGEATTENTION_VERSION=v3   # NVFP4-native, best for Blackwell — requires rebuild
SAGEATTENTION_VERSION=none # Disable entirely

# Enable/disable the global --use-sage-attention flag at startup.
# Set to 0 to keep the library installed but only activate it per-model
# using a "Patch Sage Attention" node (useful for Wan 2.1 / SD1.5 which
# can produce black frames with the global flag enabled).
SAGEATTENTION_USE=1
```

Changing `SAGEATTENTION_VERSION` requires a rebuild:
```bash
docker-compose build --no-cache
docker-compose up -d
```

### Nunchaku (NVFP4 Quantization Engine)

Nunchaku provides the NVFP4 inference backend. Edit `wheels.txt` with the latest wheel URL from [nunchaku releases](https://github.com/nunchaku-ai/nunchaku/releases), then rebuild:

```bash
docker-compose build --no-cache
docker-compose up -d
```

> **Note:** You may need to set `security_level = weak` in `user/__manager/config.ini` to allow Nunchaku to install via ComfyUI Manager.

### Updating PyTorch or CUDA

Edit `.env` with new wheel URLs (find them at https://download.pytorch.org/whl/), then rebuild. The wheel filename must match your CUDA version, Python version (cp312 for Ubuntu 24.04), and platform.

## Backup Your Setup

Important directories to back up:
- `custom_nodes/` — Your installed nodes
- `user/` — Your workflows and settings
- `models/` — Your downloaded models (large — can be re-downloaded)

Workflows and custom node configurations are unique to you and can't be recovered if lost.

## License

MIT License — See LICENSE file for details
