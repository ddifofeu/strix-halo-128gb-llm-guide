#!/usr/bin/env bash
set -uo pipefail

echo '=== CPU / kernel ==='
grep -m1 'model name' /proc/cpuinfo || true
uname -a

echo
echo '=== Memory / swap ==='
free -h
swapon --show || true

echo
echo '=== AMD GPU ==='
lspci -nnk 2>/dev/null | grep -A3 -Ei 'VGA|Display|3D' || true

echo
echo '=== AMDGPU VRAM/GTT ==='
for f in /sys/class/drm/card*/device/mem_info_vram_{total,used} \
         /sys/class/drm/card*/device/mem_info_gtt_{total,used}; do
  if [[ -r "$f" ]]; then
    printf '%-24s %8s MiB\n' "$(basename "$f")" "$(( $(cat "$f") / 1024 / 1024 ))"
  fi
done

echo
echo '=== Kernel command line ==='
cat /proc/cmdline

echo
echo '=== llama.cpp Vulkan ==='
if command -v llama-bench >/dev/null 2>&1; then
  llama-bench --version
  llama-bench --list-devices
  echo
  llama-bench --help 2>&1 | grep -E 'load-mode|lazy-mode|gpu-layers' || true
else
  echo 'llama-bench not found in PATH'
fi
