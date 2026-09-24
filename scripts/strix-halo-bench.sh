#!/usr/bin/env bash
# Strix Halo LLM Characterization Suite v3.5
# Adds explicit llama.cpp load-mode/lazy-mode A/B controls and records them in results.
# Capacity mode uses a single combined PP+TG invocation so huge models load once.

set -uo pipefail

MODEL_DIR="${MODEL_DIR:-$HOME/LLM/models}"
RESULT_ROOT="${RESULT_ROOT:-$HOME/LLM/benchmarks}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$RESULT_ROOT/$TIMESTAMP"

GPU_LAYERS="${GPU_LAYERS:-99}"
LOAD_MODE="${LOAD_MODE:-auto}"
LAZY_MODE="${LAZY_MODE:-auto}"
PROMPT_TOKENS="${PROMPT_TOKENS:-512}"
GEN_TOKENS="${GEN_TOKENS:-128}"
REPETITIONS="${REPETITIONS:-3}"
LOAD_TIMEOUT="${LOAD_TIMEOUT:-300}"
TELEMETRY_INTERVAL="${TELEMETRY_INTERVAL:-0.5}"
MAX_SWAP_GROWTH_MB="${MAX_SWAP_GROWTH_MB:-4096}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-15}"
RUN_COMBINED="${RUN_COMBINED:-1}"

MODELS=(
  "qwen3-8b|Q4_K_M|baseline"
  "mistral-small-24b|Q4_K_M|baseline"
  "qwen3-30b-a3b|Q4_K_M|moe"
  "llama33-70b|Q4_K_M|large"
  "qwen3-coder-next|Q4_K_M|cyber-code"
  "qwen3-235b-iq2m|IQ2_M|huge"
  "qwen3-235b-iq3xs|IQ3_XS|huge"
  "qwen3-235b-iq3m|IQ3_M|capacity"
  "qwen3-235b-thinking-iq2m|IQ2_M|reasoning"
)

SELECTED_MODEL=""
RUN_ALL=0
CAPACITY_MODE=0
LIST_ONLY=0

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

info()    { printf "%s[INFO]%s %s\n" "$BLUE" "$RESET" "$*"; }
ok()      { printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$*"; }
warn()    { printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$*"; }
fail()    { printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$*"; }
section() { echo; echo "================================================================"; printf "%s%s%s\n" "$BOLD" "$*" "$RESET"; echo "================================================================"; }

usage() {
  cat <<EOF2
Strix Halo LLM Characterization Suite v3.5

Usage:
  $0 --list
  $0 --model MODEL_ID [--capacity]
  $0 --all

Modes:
  --capacity   Run one combined PP+TG invocation. This loads the model once and
               is recommended for very large / boundary models.

Environment:
  MODEL_DIR=$MODEL_DIR
  RESULT_ROOT=$RESULT_ROOT
  GPU_LAYERS=$GPU_LAYERS
  LOAD_MODE=$LOAD_MODE
  LAZY_MODE=$LAZY_MODE
  PROMPT_TOKENS=$PROMPT_TOKENS
  GEN_TOKENS=$GEN_TOKENS
  REPETITIONS=$REPETITIONS
  LOAD_TIMEOUT=$LOAD_TIMEOUT
  TELEMETRY_INTERVAL=$TELEMETRY_INTERVAL
  MAX_SWAP_GROWTH_MB=$MAX_SWAP_GROWTH_MB
  RUN_COMBINED=$RUN_COMBINED
EOF2
}

while (( $# > 0 )); do
  case "$1" in
    --model)
      (( $# >= 2 )) || { fail "--model requires a model ID"; exit 1; }
      SELECTED_MODEL="$2"; shift 2 ;;
    --all)
      RUN_ALL=1; shift ;;
    --capacity)
      CAPACITY_MODE=1; shift ;;
    --list)
      LIST_ONLY=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      fail "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if (( LIST_ONLY )); then
  printf "%-30s %-12s %-14s\n" "MODEL" "QUANT" "CLASS"
  printf "%-30s %-12s %-14s\n" "-----" "-----" "-----"
  for entry in "${MODELS[@]}"; do
    IFS='|' read -r id quant class <<< "$entry"
    printf "%-30s %-12s %-14s\n" "$id" "$quant" "$class"
  done
  exit 0
fi

if [[ -z "$SELECTED_MODEL" ]] && (( ! RUN_ALL )); then
  fail "Specify --model MODEL_ID or --all"
  exit 1
fi
if [[ -n "$SELECTED_MODEL" ]] && (( RUN_ALL )); then
  fail "--model and --all are mutually exclusive"
  exit 1
fi
if (( CAPACITY_MODE )) && (( RUN_ALL )); then
  fail "--capacity is intended for a single --model run"
  exit 1
fi

for cmd in awk grep sed find free timeout date ps tee swapon sort head basename; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "Required command missing: $cmd"; exit 1; }
done

GNU_TIME=""
if [[ -x /usr/bin/time ]]; then
  GNU_TIME="/usr/bin/time"
fi

find_llama_bench() {
  if command -v llama-bench >/dev/null 2>&1; then
    command -v llama-bench
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/bin/llama-bench" \
    "$HOME/src/llama.cpp/build/bin/llama-bench" \
    "$HOME/llama.cpp/build/bin/llama-bench" \
    "/usr/local/bin/llama-bench"
  do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

LLAMA_BENCH="$(find_llama_bench || true)"
[[ -n "$LLAMA_BENCH" ]] || { fail "llama-bench not found"; exit 1; }

# Validate load controls against this installed llama-bench build.
LLAMA_HELP="$($LLAMA_BENCH --help 2>&1 || true)"
if ! grep -q -- '--load-mode' <<< "$LLAMA_HELP"; then
  fail "This llama-bench build does not expose --load-mode."
  exit 1
fi
if ! grep -q -- '--lazy-mode' <<< "$LLAMA_HELP"; then
  fail "This llama-bench build does not expose --lazy-mode."
  exit 1
fi

case "$LOAD_MODE" in
  auto|none|mmap|mlock|mmap+mlock|dio) ;;
  *) fail "Invalid LOAD_MODE=$LOAD_MODE (expected auto|none|mmap|mlock|mmap+mlock|dio)"; exit 1 ;;
esac
case "$LAZY_MODE" in
  on|auto|off) ;;
  *) fail "Invalid LAZY_MODE=$LAZY_MODE (expected on|auto|off)"; exit 1 ;;
esac

if [[ "$LOAD_MODE" == "none" && "$LAZY_MODE" != "off" ]]; then
  warn "LOAD_MODE=none with LAZY_MODE=$LAZY_MODE: upstream documents lazy loading as requiring mmap."
  warn "For a controlled no-mmap experiment, use LAZY_MODE=off."
fi

model_exists_in_catalog() {
  local requested="$1" entry id quant class
  for entry in "${MODELS[@]}"; do
    IFS='|' read -r id quant class <<< "$entry"
    [[ "$id" == "$requested" ]] && return 0
  done
  return 1
}

if [[ -n "$SELECTED_MODEL" ]] && ! model_exists_in_catalog "$SELECTED_MODEL"; then
  fail "Unknown model: $SELECTED_MODEL"
  exit 1
fi

mkdir -p "$RESULT_DIR"

get_model_entrypoint() {
  local dir="$1" first
  [[ -d "$dir" ]] || return 1
  first="$(find "$dir" -maxdepth 1 -type f -name '*-00001-of-*.gguf' | sort | head -1)"
  if [[ -n "$first" ]]; then
    echo "$first"
    return 0
  fi
  find "$dir" -maxdepth 1 -type f -name '*.gguf' | sort | head -1
}

model_size_bytes() {
  find "$1" -maxdepth 1 -type f -name '*.gguf' -printf '%s\n' 2>/dev/null \
    | awk '{s += $1} END {print s+0}'
}

mem_available_mb() {
  awk '/MemAvailable:/ {printf "%d", $2/1024; exit}' /proc/meminfo
}

swap_used_mb() {
  awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {printf "%d", (t-f)/1024}' /proc/meminfo
}

read_drm_bytes() {
  local item="$1" device
  for device in /sys/class/drm/card*/device; do
    if [[ -r "$device/$item" ]]; then
      cat "$device/$item" 2>/dev/null
      return 0
    fi
  done
  echo 0
}

bytes_to_mb() {
  local value="${1:-0}"
  [[ "$value" =~ ^[0-9]+$ ]] && echo $((value / 1024 / 1024)) || echo 0
}

read_hwmon_temp() {
  local wanted="$1" hwmon name input value
  for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r "$hwmon/name" ]] || continue
    name="$(cat "$hwmon/name" 2>/dev/null || true)"
    [[ "$name" == "$wanted" ]] || continue
    for input in "$hwmon"/temp*_input; do
      [[ -r "$input" ]] || continue
      value="$(cat "$input" 2>/dev/null || true)"
      if [[ "$value" =~ ^[0-9]+$ ]]; then
        awk -v x="$value" 'BEGIN {printf "%.1f", x/1000}'
        return 0
      fi
    done
  done
}

# System VM counters. pgpgin/pgpgout are reported by /proc/vmstat in KiB.
# Output: pgfault pgmajfault pswpin pswpout pgpgin pgpgout
read_vmstat_counters() {
  awk '
    $1=="pgfault"    {pgf=$2}
    $1=="pgmajfault" {pgm=$2}
    $1=="pswpin"     {swi=$2}
    $1=="pswpout"    {swo=$2}
    $1=="pgpgin"     {pgi=$2}
    $1=="pgpgout"    {pgo=$2}
    END {printf "%d,%d,%d,%d,%d,%d\n", pgf+0,pgm+0,swi+0,swo+0,pgi+0,pgo+0}
  ' /proc/vmstat
}

# Linux diskstats sector counts use 512-byte sectors. Sum only whole NVMe devices,
# not their partitions, to avoid double-counting.
# Output: sectors_read sectors_written
read_nvme_sectors() {
  awk '
    $3 ~ /^nvme[0-9]+n[0-9]+$/ {r += $6; w += $10}
    END {printf "%.0f,%.0f\n", r+0, w+0}
  ' /proc/diskstats
}

# Return root PID plus all current descendants.
process_tree_pids() {
  local root="$1"
  ps -eo pid=,ppid= | awk -v root="$root" '
    { parent[$1]=$2 }
    END {
      keep[root]=1
      changed=1
      while (changed) {
        changed=0
        for (p in parent) {
          if (keep[parent[p]] && !keep[p]) {
            keep[p]=1
            changed=1
          }
        }
      }
      for (p in keep) print p
    }
  '
}

# Find the actual llama-bench PID under the wrapper tree. We deliberately avoid
# aggregating /proc/<pid>/io and raw fault counters across the wrapper tree:
# those counters proved misleading on this UMA/Vulkan stack in v3.3.
find_llama_pid() {
  local root="$1" pid comm exe base
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ -r "/proc/$pid/comm" ]] || continue
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    if [[ "$comm" == "llama-bench" ]]; then
      echo "$pid"
      return 0
    fi
    if [[ -L "/proc/$pid/exe" ]]; then
      exe="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
      base="$(basename "$exe" 2>/dev/null || true)"
      if [[ "$base" == "llama-bench" ]]; then
        echo "$pid"
        return 0
      fi
    fi
  done < <(process_tree_pids "$root")
  return 1
}

sample_llama_memory() {
  local pid="$1" rss=0 vsz=0
  if [[ -n "$pid" ]] && [[ -r "/proc/$pid/status" ]]; then
    rss="$(awk '/^VmRSS:/ {printf "%d", $2/1024; exit}' "/proc/$pid/status" 2>/dev/null || echo 0)"
    vsz="$(awk '/^VmSize:/ {printf "%d", $2/1024; exit}' "/proc/$pid/status" 2>/dev/null || echo 0)"
  fi
  printf "%s,%s\n" "${rss:-0}" "${vsz:-0}"
}

TELEMETRY="$RESULT_DIR/telemetry.csv"
echo "timestamp,elapsed_s,model,phase,wrapper_pid,llama_pid,rss_mb,vsz_mb,mem_available_mb,swap_used_mb,vram_used_mb,gtt_used_mb,cpu_temp_c,gpu_temp_c,nvme_temp_c,vm_pgfault_delta,vm_pgmajfault_delta,vm_pswpin_delta,vm_pswpout_delta,vm_pgpgin_kib_delta,vm_pgpgout_kib_delta,nvme_read_bytes_delta,nvme_write_bytes_delta" > "$TELEMETRY"

PHASE_SUMMARY="$RESULT_DIR/phase-summary.csv"
echo "model,phase,load_mode,lazy_mode,status,wall_s,pp_tps,tg_tps,min_mem_available_mb,max_swap_mb,max_vram_mb,max_gtt_mb,max_llama_rss_mb,max_llama_vsz_mb,vm_pgfault_delta,vm_pgmajfault_delta,vm_pswpin_delta,vm_pswpout_delta,vm_pgpgin_kib_delta,vm_pgpgout_kib_delta,nvme_read_bytes_delta,nvme_write_bytes_delta,time_max_rss_kb,time_major_faults,time_minor_faults,time_fs_inputs,time_fs_outputs" > "$PHASE_SUMMARY"

TELEMETRY_PID=""

telemetry_loop() {
  local model="$1" phase="$2" root_pid="$3"
  local base_vm="$4" base_disk="$5"
  local base_pgf base_pgm base_swi base_swo base_pgi base_pgo
  local base_dr base_dw
  local start_ns now_ns elapsed llama_pid memstats rss_mb vsz_mb
  local mem_mb swap_mb vram_mb gtt_mb cpu_temp gpu_temp nvme_temp
  local vm now_pgf now_pgm now_swi now_swo now_pgi now_pgo
  local disk now_dr now_dw
  local alive=1 final_sample=0

  IFS=',' read -r base_pgf base_pgm base_swi base_swo base_pgi base_pgo <<< "$base_vm"
  IFS=',' read -r base_dr base_dw <<< "$base_disk"
  start_ns="$(date +%s%N)"

  while :; do
    if kill -0 "$root_pid" 2>/dev/null; then
      alive=1
    else
      alive=0
      (( final_sample == 0 )) || break
      final_sample=1
    fi

    now_ns="$(date +%s%N)"
    elapsed="$(awk -v s="$start_ns" -v n="$now_ns" 'BEGIN {printf "%.3f", (n-s)/1000000000}')"

    llama_pid="$(find_llama_pid "$root_pid" 2>/dev/null || true)"
    memstats="$(sample_llama_memory "$llama_pid")"
    IFS=',' read -r rss_mb vsz_mb <<< "$memstats"

    mem_mb="$(mem_available_mb)"
    swap_mb="$(swap_used_mb)"
    vram_mb="$(bytes_to_mb "$(read_drm_bytes mem_info_vram_used)")"
    gtt_mb="$(bytes_to_mb "$(read_drm_bytes mem_info_gtt_used)")"
    cpu_temp="$(read_hwmon_temp k10temp)"
    gpu_temp="$(read_hwmon_temp amdgpu)"
    nvme_temp="$(read_hwmon_temp nvme)"

    vm="$(read_vmstat_counters)"
    IFS=',' read -r now_pgf now_pgm now_swi now_swo now_pgi now_pgo <<< "$vm"

    disk="$(read_nvme_sectors)"
    IFS=',' read -r now_dr now_dw <<< "$disk"

    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%.0f,%.0f\n" \
      "$(date -Is)" "$elapsed" "$model" "$phase" "$root_pid" "${llama_pid:-0}" \
      "${rss_mb:-0}" "${vsz_mb:-0}" "$mem_mb" "$swap_mb" "$vram_mb" "$gtt_mb" \
      "${cpu_temp:-}" "${gpu_temp:-}" "${nvme_temp:-}" \
      "$((now_pgf-base_pgf))" "$((now_pgm-base_pgm))" \
      "$((now_swi-base_swi))" "$((now_swo-base_swo))" \
      "$((now_pgi-base_pgi))" "$((now_pgo-base_pgo))" \
      "$(((now_dr-base_dr)*512))" "$(((now_dw-base_dw)*512))" >> "$TELEMETRY"

    (( alive == 0 )) && break
    sleep "$TELEMETRY_INTERVAL"
  done
}

start_telemetry() {
  local model="$1" phase="$2" root_pid="$3" base_vm="$4" base_disk="$5"
  telemetry_loop "$model" "$phase" "$root_pid" "$base_vm" "$base_disk" &
  TELEMETRY_PID=$!
}

stop_telemetry() {
  if [[ -n "${TELEMETRY_PID:-}" ]]; then
    wait "$TELEMETRY_PID" 2>/dev/null || true
    TELEMETRY_PID=""
  fi
}
trap '[[ -n "${TELEMETRY_PID:-}" ]] && kill "$TELEMETRY_PID" 2>/dev/null || true' EXIT INT TERM

extract_pp() {
  grep -E '\|[[:space:]]*pp[0-9]+' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*|[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*±.*/\1/p'
}

extract_tg() {
  grep -E '\|[[:space:]]*tg[0-9]+' "$1" 2>/dev/null | tail -1 \
    | sed -n 's/.*|[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*±.*/\1/p'
}

# Per-phase live telemetry summary.
# Output:
# min_mem,max_swap,max_vram,max_gtt,max_rss,max_vsz,pgf,pgmaj,swi,swo,pgi,pgo,nvread,nvwrite
telemetry_phase_summary() {
  local model="$1" phase="$2"
  awk -F',' -v model="$model" -v phase="$phase" '
    NR==1 {next}
    $3==model && $4==phase {
      if (!seen || $9 < min_mem) min_mem=$9
      if (!seen || $10 > max_swap) max_swap=$10
      if (!seen || $11 > max_vram) max_vram=$11
      if (!seen || $12 > max_gtt) max_gtt=$12
      if (!seen || $7 > max_rss) max_rss=$7
      if (!seen || $8 > max_vsz) max_vsz=$8
      if (!seen || $16 > pgf) pgf=$16
      if (!seen || $17 > pgmaj) pgmaj=$17
      if (!seen || $18 > swi) swi=$18
      if (!seen || $19 > swo) swo=$19
      if (!seen || $20 > pgi) pgi=$20
      if (!seen || $21 > pgo) pgo=$21
      if (!seen || $22 > nvr) nvr=$22
      if (!seen || $23 > nvw) nvw=$23
      seen=1
    }
    END {
      if (!seen) print "0,0,0,0,0,0,0,0,0,0,0,0,0,0"
      else printf "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.0f,%.0f\n", \
        min_mem,max_swap,max_vram,max_gtt,max_rss,max_vsz,pgf,pgmaj,swi,swo,pgi,pgo,nvr,nvw
    }
  ' "$TELEMETRY"
}

parse_gnu_time() {
  local file="$1" key
  local maxrss=0 maj=0 min=0 fsin=0 fsout=0
  if [[ -r "$file" ]]; then
    maxrss="$(awk -F: '/Maximum resident set size \(kbytes\)/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$file")"
    maj="$(awk -F: '/Major \(requiring I\/O\) page faults/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$file")"
    min="$(awk -F: '/Minor \(reclaiming a frame\) page faults/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$file")"
    fsin="$(awk -F: '/File system inputs/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$file")"
    fsout="$(awk -F: '/File system outputs/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$file")"
  fi
  printf "%s,%s,%s,%s,%s\n" "${maxrss:-0}" "${maj:-0}" "${min:-0}" "${fsin:-0}" "${fsout:-0}"
}

SUMMARY="$RESULT_DIR/summary.csv"
echo "model,quant,class,size_gib,gpu_layers,load_mode,lazy_mode,status,pp_tps,tg_tps,elapsed_s,min_mem_available_mb,max_swap_mb,max_vram_mb,max_gtt_mb,max_llama_rss_mb,max_llama_vsz_mb,vm_pgfault_delta,vm_pgmajfault_delta,vm_pswpin_delta,vm_pswpout_delta,vm_pgpgin_kib_delta,vm_pgpgout_kib_delta,nvme_read_bytes_delta,nvme_write_bytes_delta" > "$SUMMARY"

LAST_ELAPSED="0"
LAST_RC=0
LAST_LOG=""
LAST_PHASE=""
LAST_TIME_LOG=""
LAST_PP=""
LAST_TG=""
LAST_PHASE_METRICS="0,0,0,0,0,0,0,0,0,0,0,0,0,0"
LAST_TIME_METRICS="0,0,0,0,0"

run_llama_bench() {
  local id="$1" model="$2" prompt="$3" generation="$4" phase="$5"
  local log="$RESULT_DIR/${id}-${phase}.log"
  local time_log="$RESULT_DIR/${id}-${phase}.time.txt"
  local start_ns end_ns wrapper_pid rc base_vm base_disk
  local min_mem max_swap max_vram max_gtt max_rss max_vsz pgf pgmaj swi swo pgi pgo nvr nvw
  local t_rss t_maj t_min t_in t_out phase_status

  LAST_LOG="$log"
  LAST_PHASE="$phase"
  LAST_TIME_LOG="$time_log"
  LAST_PP=""
  LAST_TG=""
  : > "$log"
  : > "$time_log"

  base_vm="$(read_vmstat_counters)"
  base_disk="$(read_nvme_sectors)"
  start_ns="$(date +%s%N)"

  if [[ -n "$GNU_TIME" ]]; then
    LC_ALL=C "$GNU_TIME" -v -o "$time_log" \
      timeout --signal=INT --kill-after=20s "${LOAD_TIMEOUT}s" \
        "$LLAMA_BENCH" \
          -m "$model" \
          -ngl "$GPU_LAYERS" \
          -lm "$LOAD_MODE" \
          -lzm "$LAZY_MODE" \
          -p "$prompt" \
          -n "$generation" \
          -r "$REPETITIONS" \
          > >(tee -a "$log") \
          2> >(tee -a "$log" >&2) &
  else
    timeout --signal=INT --kill-after=20s "${LOAD_TIMEOUT}s" \
      "$LLAMA_BENCH" \
        -m "$model" \
        -ngl "$GPU_LAYERS" \
        -lm "$LOAD_MODE" \
        -lzm "$LAZY_MODE" \
        -p "$prompt" \
        -n "$generation" \
        -r "$REPETITIONS" \
        > >(tee -a "$log") \
        2> >(tee -a "$log" >&2) &
  fi

  wrapper_pid=$!
  start_telemetry "$id" "$phase" "$wrapper_pid" "$base_vm" "$base_disk"

  wait "$wrapper_pid"
  rc=$?
  stop_telemetry

  end_ns="$(date +%s%N)"
  LAST_ELAPSED="$(awk -v s="$start_ns" -v n="$end_ns" 'BEGIN {printf "%.3f", (n-s)/1000000000}')"
  LAST_RC=$rc
  LAST_PP="$(extract_pp "$log")"
  LAST_TG="$(extract_tg "$log")"
  LAST_PHASE_METRICS="$(telemetry_phase_summary "$id" "$phase")"
  LAST_TIME_METRICS="$(parse_gnu_time "$time_log")"

  IFS=',' read -r min_mem max_swap max_vram max_gtt max_rss max_vsz pgf pgmaj swi swo pgi pgo nvr nvw <<< "$LAST_PHASE_METRICS"
  IFS=',' read -r t_rss t_maj t_min t_in t_out <<< "$LAST_TIME_METRICS"

  if (( rc == 0 )); then phase_status="pass"
  elif (( rc == 124 )); then phase_status="timeout"
  elif (( rc == 130 )); then phase_status="interrupted"
  else phase_status="failed"
  fi

  echo "$id,$phase,$LOAD_MODE,$LAZY_MODE,$phase_status,$LAST_ELAPSED,${LAST_PP:-},${LAST_TG:-},$min_mem,$max_swap,$max_vram,$max_gtt,$max_rss,$max_vsz,$pgf,$pgmaj,$swi,$swo,$pgi,$pgo,$nvr,$nvw,$t_rss,$t_maj,$t_min,$t_in,$t_out" >> "$PHASE_SUMMARY"

  return "$rc"
}

# Aggregate live telemetry over all phases for one model.
# Output same 14 columns as telemetry_phase_summary.
telemetry_model_summary() {
  local model="$1"
  awk -F',' -v model="$model" '
    NR==1 {next}
    $3==model {
      if (!seen || $9 < min_mem) min_mem=$9
      if (!seen || $10 > max_swap) max_swap=$10
      if (!seen || $11 > max_vram) max_vram=$11
      if (!seen || $12 > max_gtt) max_gtt=$12
      if (!seen || $7 > max_rss) max_rss=$7
      if (!seen || $8 > max_vsz) max_vsz=$8
      if (!seen || $16 > pgf) pgf=$16
      if (!seen || $17 > pgmaj) pgmaj=$17
      if (!seen || $18 > swi) swi=$18
      if (!seen || $19 > swo) swo=$19
      if (!seen || $20 > pgi) pgi=$20
      if (!seen || $21 > pgo) pgo=$21
      if (!seen || $22 > nvr) nvr=$22
      if (!seen || $23 > nvw) nvw=$23
      seen=1
    }
    END {
      if (!seen) print "0,0,0,0,0,0,0,0,0,0,0,0,0,0"
      else printf "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.0f,%.0f\n", \
        min_mem,max_swap,max_vram,max_gtt,max_rss,max_vsz,pgf,pgmaj,swi,swo,pgi,pgo,nvr,nvw
    }
  ' "$TELEMETRY"
}

benchmark_model() {
  local id="$1" quant="$2" class="$3"
  local dir="$MODEL_DIR/$id" model size_bytes size_gib
  local swap_before swap_after swap_delta total_start total_end total_elapsed
  local status="pass" pp="" tg="" rc
  local min_mem max_swap max_vram max_gtt max_rss max_vsz pgf pgmaj swi swo pgi pgo nvr nvw

  model="$(get_model_entrypoint "$dir" || true)"
  if [[ -z "$model" ]]; then
    warn "Model not found: $id"
    return 0
  fi

  size_bytes="$(model_size_bytes "$dir")"
  size_gib="$(awk -v x="$size_bytes" 'BEGIN {printf "%.2f", x/1024/1024/1024}')"

  section "MODEL: $id"
  echo "Quantization:      $quant"
  echo "Class:             $class"
  echo "Model size:        ${size_gib} GiB"
  echo "GPU layers:        $GPU_LAYERS"
  echo "Load mode:         $LOAD_MODE"
  echo "Lazy mode:         $LAZY_MODE"
  echo "Timeout/test:      ${LOAD_TIMEOUT}s"
  echo "Telemetry:         ${TELEMETRY_INTERVAL}s"
  echo "Capacity mode:     $CAPACITY_MODE"
  echo "Entrypoint:        $model"

  swap_before="$(swap_used_mb)"
  total_start="$(date +%s%N)"

  if (( CAPACITY_MODE )); then
    info "Capacity test: one combined PP${PROMPT_TOKENS} + TG${GEN_TOKENS} invocation"
    if run_llama_bench "$id" "$model" "$PROMPT_TOKENS" "$GEN_TOKENS" "capacity"; then
      pp="$LAST_PP"
      tg="$LAST_TG"
      [[ -n "$pp" ]] && ok "PP${PROMPT_TOKENS}: $pp tok/s"
      [[ -n "$tg" ]] && ok "TG${GEN_TOKENS}: $tg tok/s"
    else
      rc=$LAST_RC
      if (( rc == 124 )); then status="timeout"
      elif (( rc == 130 )); then status="interrupted"
      else status="failed"
      fi
      warn "Capacity run ended with status: $status (exit $rc)"
    fi
  else
    info "PP${PROMPT_TOKENS} test"
    if run_llama_bench "$id" "$model" "$PROMPT_TOKENS" 0 "pp"; then
      pp="$LAST_PP"
      [[ -n "$pp" ]] && ok "PP${PROMPT_TOKENS}: $pp tok/s"
    else
      rc=$LAST_RC
      if (( rc == 124 )); then status="timeout"
      elif (( rc == 130 )); then status="interrupted"
      else status="failed"
      fi
      warn "PP run ended with status: $status (exit $rc)"
    fi

    if [[ "$status" == "pass" ]]; then
      info "TG${GEN_TOKENS} test"
      if run_llama_bench "$id" "$model" 0 "$GEN_TOKENS" "tg"; then
        tg="$LAST_TG"
        [[ -n "$tg" ]] && ok "TG${GEN_TOKENS}: $tg tok/s"
      else
        rc=$LAST_RC
        if (( rc == 124 )); then status="timeout"
        elif (( rc == 130 )); then status="interrupted"
        else status="failed"
        fi
        warn "TG run ended with status: $status (exit $rc)"
      fi
    fi

    if [[ "$status" == "pass" ]] && (( RUN_COMBINED )); then
      info "Combined PP${PROMPT_TOKENS} + TG${GEN_TOKENS}"
      if ! run_llama_bench "$id" "$model" "$PROMPT_TOKENS" "$GEN_TOKENS" "combined"; then
        warn "Combined test failed or timed out (exit $LAST_RC); separate PP/TG results retained"
      fi
    fi
  fi

  total_end="$(date +%s%N)"
  total_elapsed="$(awk -v s="$total_start" -v n="$total_end" 'BEGIN {printf "%.3f", (n-s)/1000000000}')"

  IFS=',' read -r min_mem max_swap max_vram max_gtt max_rss max_vsz pgf pgmaj swi swo pgi pgo nvr nvw \
    <<< "$(telemetry_model_summary "$id")"

  echo "$id,$quant,$class,$size_gib,$GPU_LAYERS,$LOAD_MODE,$LAZY_MODE,$status,${pp:-},${tg:-},$total_elapsed,$min_mem,$max_swap,$max_vram,$max_gtt,$max_rss,$max_vsz,$pgf,$pgmaj,$swi,$swo,$pgi,$pgo,$nvr,$nvw" >> "$SUMMARY"

  echo
  echo "---------------- RESULT ----------------"
  echo "Status:                   $status"
  echo "PP:                       ${pp:-N/A} tok/s"
  echo "TG:                       ${tg:-N/A} tok/s"
  echo "Elapsed:                  ${total_elapsed}s"
  echo "Minimum available RAM:    ${min_mem} MB"
  echo "Maximum swap:             ${max_swap} MB"
  echo "Maximum VRAM used:        ${max_vram} MB"
  echo "Maximum GTT used:         ${max_gtt} MB"
  echo "Maximum llama RSS:        ${max_rss} MB"
  echo "Maximum llama VSZ:        ${max_vsz} MB"
  echo "VM page faults delta:     ${pgf}"
  echo "VM major faults delta:    ${pgmaj}"
  echo "Swap-in pages delta:      ${swi}"
  echo "Swap-out pages delta:     ${swo}"
  echo "VM pgpgin delta:          ${pgi} KiB"
  echo "VM pgpgout delta:         ${pgo} KiB"
  echo "NVMe read delta:          ${nvr} bytes"
  echo "NVMe write delta:         ${nvw} bytes"
  echo "----------------------------------------"

  swap_after="$(swap_used_mb)"
  swap_delta=$((swap_after - swap_before))
  (( swap_delta < 0 )) && swap_delta=0

  if (( swap_delta > MAX_SWAP_GROWTH_MB )); then
    warn "Swap increased by ${swap_delta} MB; safety threshold exceeded"
    return 2
  fi

  [[ "$status" == "pass" ]] || return 1
  return 0
}

FINAL_EXIT=0

section "STRIX HALO CHARACTERIZATION v3.5"
echo "Started:             $(date -Is)"
echo "Hostname:            $(hostname)"
echo "Model directory:     $MODEL_DIR"
echo "Results:             $RESULT_DIR"
echo "GPU layers:          $GPU_LAYERS"
echo "Load mode:           $LOAD_MODE"
echo "Lazy mode:           $LAZY_MODE"
echo "Timeout/test:        ${LOAD_TIMEOUT}s"
echo "Telemetry interval:  ${TELEMETRY_INTERVAL}s"
echo "GNU time:            ${GNU_TIME:-not available}"

echo
echo "Memory:"
free -h

echo
echo "Kernel:"
uname -a

echo
echo "llama.cpp:"
"$LLAMA_BENCH" --version 2>&1 || true

echo
echo "Devices:"
"$LLAMA_BENCH" --list-devices 2>&1 || true

if [[ -n "$SELECTED_MODEL" ]]; then
  for entry in "${MODELS[@]}"; do
    IFS='|' read -r id quant class <<< "$entry"
    [[ "$id" == "$SELECTED_MODEL" ]] || continue
    benchmark_model "$id" "$quant" "$class"
    result=$?
    (( result == 2 )) && warn "Memory-pressure threshold exceeded"
    (( result != 0 )) && FINAL_EXIT="$result"
    break
  done
fi

if (( RUN_ALL )); then
  for entry in "${MODELS[@]}"; do
    IFS='|' read -r id quant class <<< "$entry"
    benchmark_model "$id" "$quant" "$class"
    result=$?
    if (( result != 0 )); then
      FINAL_EXIT="$result"
      warn "Stopping escalation after $id"
      break
    fi
    info "Cooling / settling for ${COOLDOWN_SECONDS}s"
    sleep "$COOLDOWN_SECONDS"
  done
fi

section "FINAL SYSTEM STATE"
free -h

echo
echo "Swap:"
swapon --show

echo
echo "AMDGPU memory:"
echo "VRAM used: $(bytes_to_mb "$(read_drm_bytes mem_info_vram_used)") MB"
echo "GTT used:  $(bytes_to_mb "$(read_drm_bytes mem_info_gtt_used)") MB"

echo
echo "Temperatures:"
for sensor in k10temp amdgpu nvme; do
  temperature="$(read_hwmon_temp "$sensor")"
  [[ -n "$temperature" ]] && echo "$sensor: ${temperature} C"
done

echo
echo "Relevant kernel messages:"
dmesg 2>/dev/null \
  | grep -Ei 'amdgpu.*(error|fail|timeout|reset|fault)|oom|out of memory|thermal.*thrott' \
  | tail -100 || true

section "COMPLETE"
echo "Results:"
echo "    $RESULT_DIR"
echo
echo "Summary:"
echo "    $SUMMARY"
echo
echo "Per-phase summary:"
echo "    $PHASE_SUMMARY"
echo
echo "Full telemetry:"
echo "    $TELEMETRY"
echo
echo "Finished:"
date -Is

exit "$FINAL_EXIT"