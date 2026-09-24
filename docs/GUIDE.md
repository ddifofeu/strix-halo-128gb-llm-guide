# Bosgame Strix Halo 128 GB Local LLM Guide

**Version:** 1.0 — 24 September 2026  
**Scope:** Large GGUF inference with llama.cpp/Vulkan on a Bosgame M5-class 128 GB Strix Halo system.

## Executive summary

The central result is simple: **fixed UMA size determines the practical upper model boundary.** On the tested 128 GB Ryzen AI MAX+ 395 system, 64 GiB UMA was excellent up to the ~90 GiB model class, but Qwen3 235B IQ3_M (~100 GiB) crossed a severe GTT/reclaim cliff and never reached inference within 600 seconds. Changing only the firmware UMA reservation to 96 GiB turned the same model into a stable ~17 tok/s workload with zero meaningful swap.

This did **not** materially hurt the tested 5–45 GiB models. Therefore, for an LLM-first 128 GB Strix Halo workstation, 96 GiB `UMA_SPECIFIED` is the measured preferred profile. For a mixed desktop/VM workstation, 64 GiB remains reasonable if ~100 GiB models are not a goal.

## 1. Test platform

- Bosgame M5 / AMD Ryzen AI MAX+ 395
- 128 GB physical RAM
- Radeon 8060S integrated GPU, GFX1151
- Ubuntu 24.04.5 LTS
- Kernel 6.17.0-35-generic
- RADV Vulkan backend
- llama.cpp build 11149 (`d2e54583c`)
- Vulkan device reported as UMA-capable
- No full system ROCm installation was required for these results

### Test-host memory parameters

The benchmark host had an unusually large GTT aperture configured:

```text
amdgpu.gttsize=114688
ttm.pages_limit=30720000
```

This is part of the test description, **not a blanket recommendation**. Current Linux kernel docs mark `amdgpu.gttsize` deprecated. The experiment did not isolate either boot parameter.

## 2. BIOS recommendation

### AI-first profile

```text
iGPU Configuration:      UMA_SPECIFIED
UMA Frame Buffer Size:   96G
```

Observed after reboot:

```text
Linux-visible RAM:       ~30 GiB
Fixed VRAM/UMA:          98,304 MiB
GTT aperture:            114,688 MiB
Vulkan addressable:      212,992 MiB
```

### Mixed-workstation profile

64 GiB UMA leaves roughly 62 GiB visible to Linux and is more comfortable for heavy desktop applications, VMs and containers. In these measurements it still ran Qwen3 235B IQ3_XS (~90 GiB) at ~17.8 tok/s, but it could not run IQ3_M (~100 GiB) without severe thrashing.

### Why not BIOS Auto?

`Auto` was not benchmarked. A shareable guide should not claim it is equivalent to a fixed 64 or 96 GiB reservation.

## 3. Build llama.cpp with Vulkan

Upstream llama.cpp documents the `GGML_VULKAN=ON` build option and states that `-ngl 99` should offload all layers for most models.

```bash
sudo apt update
sudo apt install -y \
  git build-essential cmake ninja-build \
  libvulkan-dev vulkan-tools glslc spirv-headers libssl-dev

mkdir -p ~/src
cd ~/src
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=ON

cmake --build build -j"$(nproc)"
```

Check the device:

```bash
./build/bin/llama-bench --version
./build/bin/llama-bench --list-devices
```

Expected family of output:

```text
ggml_vulkan: ... AMD Radeon Graphics (RADV GFX1151) ... uma: 1
```

## 4. Runtime parameters

The measured default recommendation is:

```text
backend       Vulkan / RADV
GPU layers    99
load mode     auto
lazy mode     auto
```

The test build exposed:

```text
-lm,  --load-mode <auto|none|mmap|mlock|mmap+mlock|dio>
-lzm, --lazy-mode <on|auto|off>
```

A no-mmap experiment (`none/off`) did **not** solve the 64 GiB UMA IQ3_M failure. At 96 GiB UMA both loader modes worked and `auto/auto` was marginally cleaner, including zero major faults in the measured run.

## 5. Swap

Recommended ordering from the measured setup:

```text
zram      priority 100
disk swap priority -2
```

Check with:

```bash
swapon --show
```

Do not interpret large swap as successful model offload. In the 64 GiB IQ3_M failure the machine remained stable, but sustained reclaim prevented the benchmark from reaching inference.

## 6. Benchmark method

The core benchmark used:

```text
llama-bench
GPU layers: 99
PP: 512 tokens
TG: 128 tokens
Repetitions: 3
```

`PP512` measures prompt-processing throughput. `TG128` measures token generation. The benchmark harness additionally samples RAM, swap, VRAM, GTT, temperatures and VM paging counters.

These figures should be treated as **throughput/capacity numbers**, not model-quality rankings.

## 7. Results

### 64 GiB UMA baseline

| Model | Quant | GGUF | PP512 | TG128 |
|---|---|---:|---:|---:|
| Qwen3 8B | Q4_K_M | 4.68 GiB | 1055.49 | 40.96 |
| Mistral Small 3.1 24B | Q4_K_M | 13.35 GiB | 358.88 | 14.26 |
| Qwen3 30B-A3B | Q4_K_M | 17.35 GiB | 1279.09 | **85.50** |
| Llama 3.3 70B | Q4_K_M | 39.60 GiB | 106.02 | 4.81 |
| Qwen3-Coder-Next | Q4_K_M | 45.09 GiB | 750.90 | **57.42** |
| Qwen3 235B-A22B | IQ2_M | 73.16 GiB | 163.06 | 20.07 |
| Qwen3 235B-A22B | IQ3_XS | 90.25 GiB | 164.78 | 17.81 |
| Qwen3 235B-A22B | IQ3_M | 99.96 GiB | timeout | timeout |

### 96 GiB UMA validation

| Model | Quant | GGUF | PP512 | TG128 | Peak GTT |
|---|---|---:|---:|---:|---:|
| Qwen3 8B | Q4_K_M | 4.68 GiB | 1056.98 | 41.35 | 452 MiB |
| Qwen3 30B-A3B | Q4_K_M | 17.35 GiB | 1279.60 | **85.52** | 274 MiB |
| Qwen3-Coder-Next | Q4_K_M | 45.09 GiB | 747.41 | **57.53** | 273 MiB |
| Qwen3 235B-A22B | IQ3_XS | 90.25 GiB | 169.26 | **18.07** | 369 MiB |
| Qwen3 235B-A22B | IQ3_M | 99.96 GiB | 165.94 | **17.05** | 5,697 MiB |

Small/mid-size performance stayed within normal run-to-run noise when moving from 64 to 96 GiB UMA.

## 8. The ~100 GiB memory cliff

### 64 GiB UMA, auto/auto

Qwen3 235B IQ3_M never reached PP/TG within 600 s:

```text
Peak VRAM:               65,395 MiB
Peak GTT:                38,645 MiB
Minimum available RAM:    2,678 MiB
Peak swap:                4,025 MiB
Major faults:           193,127
Result:                  TIMEOUT
```

### 64 GiB UMA, none/off

Changing the loader did not fix it:

```text
Peak VRAM:               65,350 MiB
Peak GTT:                38,644 MiB
Minimum available RAM:    1,066 MiB
Peak swap:                3,850 MiB
Major faults:           234,957
Result:                  TIMEOUT
```

### 96 GiB UMA, auto/auto

The same ~100 GiB model completed cleanly:

```text
PP512:                   165.94 tok/s
TG128:                    17.05 tok/s
Peak VRAM:               98,233 MiB
Peak GTT:                 5,697 MiB
Minimum available RAM:   13,264 MiB
Peak swap:                    0 MiB
Major faults:                 0
Result:                  PASS
```

The evidence supports a GTT/reclaim cliff at 64 GiB UMA for this workload. Increasing fixed UMA allowed almost all of the GPU working allocation to remain in the direct UMA region.

## 9. Performance-oriented model recommendations

### Best throughput / general work

**Qwen3 30B-A3B Q4_K_M**  
Measured ~85.5 tok/s generation. This was the fastest tested model despite its larger total parameter count, illustrating the strong fit between sparse MoE inference and this memory-rich APU.

### Coding / engineering

**Qwen3-Coder-Next Q4_K_M**  
Measured ~57.5 tok/s generation at a ~45 GiB GGUF footprint. This is the most attractive measured coding-oriented daily driver.

### Compact

**Qwen3 8B Q4_K_M**  
Measured ~41.4 tok/s at 96 GiB UMA and requires little memory.

### Very large model balance

**Qwen3 235B IQ3_XS**  
Measured ~18.1 tok/s at ~90 GiB. At 96 GiB UMA it used only ~369 MiB peak GTT in the measured run. This is the recommended large-model balance point from a capacity/throughput perspective.

### Higher-bit 235B option

**Qwen3 235B IQ3_M**  
Measured ~17.1 tok/s at ~100 GiB. Use 96 GiB UMA. It consumes more memory and spills ~5.7 GiB to GTT; whether its higher quant fidelity is worth the cost should be decided with task-quality testing.

### Dense models

The tested dense models were much slower per generated token: Mistral Small 24B ~14.3 tok/s and Llama 3.3 70B ~4.8 tok/s. That is a hardware-efficiency observation, not a quality verdict.

## 10. What not to copy blindly

- Do **not** assume a 176–208 GiB Vulkan-reported address space is physical RAM.
- Do **not** treat BIOS `Auto` as equivalent to 96G.
- Do **not** copy deprecated `amdgpu.gttsize` without understanding your kernel.
- Do **not** add giant disk swap and call it model capacity.
- Do **not** infer model quality from tok/s.
- Do **not** assume full ROCm is necessary; these measurements used Vulkan/RADV.

## 11. Next benchmarks worth adding

- 8K / 32K / 64K context and KV-cache scaling
- TTFT and end-to-end interactive latency
- Flash Attention on/off/auto
- Vulkan vs a current HIP/ROCm build on the same GGUF
- Quality benchmarks comparing IQ2_M / IQ3_XS / IQ3_M
- Power-at-the-wall and sustained thermals

## Sources

Benchmark figures: measurements from the test host on 23–24 September 2026, normalized in `data/benchmarks.csv`.

Upstream references:

- https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md
- https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- https://docs.kernel.org/gpu/amdgpu/module-parameters.html
