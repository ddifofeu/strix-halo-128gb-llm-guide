# Suggested Reddit title

**I tested 512 MB vs 64 GB vs 96 GB UMA on a 128 GB Strix Halo — 512 MB is great until the large-model GTT cliff**

# Reddit-ready post

A couple of people pushed back on my original 96 GB UMA recommendation and suggested the opposite strategy: **minimum UMA (512 MB) + a large GTT aperture**.

Fair criticism. I had not tested that configuration, so I did.

Same machine, same kernel, same RADV/Vulkan backend, same llama.cpp build, same GGUFs and the same benchmark harness. My host has a 114,688 MiB GTT aperture configured, so this is specifically a test of **512 MiB fixed UMA + ~112 GiB GTT** versus fixed 64/96 GiB UMA.

## Result

512 MB UMA is genuinely good for smaller/medium models. It is **not** significantly faster than 96 GB UMA, but it leaves almost the full 128 GB available to Linux.

| Model | GGUF | 512 MB UMA | 64 GB UMA | 96 GB UMA |
|---|---:|---:|---:|---:|
| Qwen3 8B Q4_K_M | 4.68 GiB | **41.35 tok/s** | 40.96 | **41.35** |
| Qwen3-Coder-Next Q4_K_M | 45.09 GiB | **57.84 tok/s** | 57.42 | 57.53 |
| Qwen3 235B IQ2_M | 73.16 GiB | **timeout >601 s** | 20.07 | **20.40** |
| Qwen3 235B IQ3_XS | 90.25 GiB | **timeout >302 s** | 17.81 | **18.07** |
| Qwen3 235B IQ3_M | 99.96 GiB | not run | **timeout >600 s** | **17.05** |

The interesting part is where 512 MB breaks.

### 73.16 GiB IQ2_M at 512 MB UMA

I reran this one for a full 600 seconds from clean swap:

```
Peak VRAM:                458 MiB
Peak GTT:              74,985 MiB
Minimum MemAvailable:  22,308 MiB
Peak swap:                  0 MiB
Major faults:            1,021
VM page faults:      29,711,338
Elapsed:               601.178 s
Result:                TIMEOUT before PP/TG
```

So this was **not simply an OOM/swap problem**. There was still ~22 GiB available host RAM and zero swap, but llama-bench never reached inference.

The exact same 73.16 GiB GGUF at **96 GiB UMA**:

```
PP512:                 170.09 tok/s
TG128:                  20.40 tok/s
Peak VRAM:             76,128 MiB
Peak GTT:                 351 MiB
Peak swap:                  0 MiB
Elapsed:                91.004 s
Result:                  PASS
```

### 90.25 GiB IQ3_XS at 512 MB UMA

This one was worse:

```
Peak GTT:              92,558 MiB
Minimum MemAvailable:     267 MiB
Peak swap:              16.3 GiB
Major faults:        1,328,937
Result:               TIMEOUT >302 s
```

At 96 GiB UMA the same model runs at **18.07 tok/s TG128** with only ~369 MiB peak GTT.

## My conclusion changed, but not in the way I expected

I would now describe the profiles like this:

- **96 GiB UMA = AI-first profile / best tested overall for large local LLMs.** Small/medium throughput is basically unchanged, while 73–100 GiB GGUFs work cleanly.
- **64 GiB UMA = mixed-workstation compromise.** ~62 GiB remains host-visible; 73 and 90 GiB models work; the ~100 GiB model does not.
- **512 MiB UMA = host-RAM-first profile.** Excellent through at least the tested ~45 GiB class, and leaves ~124 GiB to Linux, but the tested GTT path becomes impractical somewhere between ~45 and 73 GiB.

So the people telling me to test 512 MB were right that it is a valid and useful Strix Halo configuration. On this stack, though, **large GTT addressability is not equivalent to practical fixed-UMA capacity**.

One important caveat: this is one machine and one Vulkan/RADV stack, and my host has an unusually large GTT kernel setting. `amdgpu.gttsize` is deprecated in current kernel docs, so don't blindly copy my boot parameters.

Also: these are **capacity/throughput benchmarks, not model-quality rankings**. The comment about precision/GB is fair; quality/precision-per-GiB needs a separate benchmark suite.

Repo has the raw normalized CSV, telemetry harness, charts and full guide. If anyone has reproducible 512 MB results on the same ~73–100 GiB models with a different kernel/Mesa/llama.cpp stack, I'd genuinely like to compare them.
