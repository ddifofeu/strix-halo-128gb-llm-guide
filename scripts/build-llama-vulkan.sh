#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/src/llama.cpp}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
JOBS="${JOBS:-$(nproc)}"

sudo apt update
sudo apt install -y \
  git build-essential cmake ninja-build \
  libvulkan-dev vulkan-tools glslc spirv-headers libssl-dev

mkdir -p "$(dirname "$SRC_DIR")" "$BIN_DIR"
if [[ -d "$SRC_DIR/.git" ]]; then
  git -C "$SRC_DIR" pull --ff-only
else
  git clone https://github.com/ggml-org/llama.cpp.git "$SRC_DIR"
fi

cmake -S "$SRC_DIR" -B "$SRC_DIR/build" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=ON

cmake --build "$SRC_DIR/build" --config Release -j"$JOBS"

for tool in llama-bench llama-cli llama-server; do
  if [[ -x "$SRC_DIR/build/bin/$tool" ]]; then
    ln -sf "$SRC_DIR/build/bin/$tool" "$BIN_DIR/$tool"
  fi
done

printf '\nBuilt llama.cpp Vulkan tools.\n'
"$BIN_DIR/llama-bench" --version || true
"$BIN_DIR/llama-bench" --list-devices || true
