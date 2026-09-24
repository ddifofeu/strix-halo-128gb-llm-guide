#!/usr/bin/env bash
# Resolve and download the GGUF quantizations used by the benchmark guide.
# Uses only Python stdlib + wget. Handles single-file and sharded GGUFs.
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-$HOME/LLM/models}"
mkdir -p "$MODEL_DIR"

MODELS=(
  'qwen3-8b|bartowski/Qwen_Qwen3-8B-GGUF|Q4_K_M'
  'mistral-small-24b|bartowski/mistralai_Mistral-Small-3.1-24B-Instruct-2503-GGUF|Q4_K_M'
  'qwen3-30b-a3b|bartowski/Qwen_Qwen3-30B-A3B-GGUF|Q4_K_M'
  'llama33-70b|bartowski/Llama-3.3-70B-Instruct-GGUF|Q4_K_M'
  'qwen3-coder-next|Qwen/Qwen3-Coder-Next-GGUF|Q4_K_M'
  'qwen3-235b-iq2m|bartowski/Qwen_Qwen3-235B-A22B-Instruct-2507-GGUF|IQ2_M'
  'qwen3-235b-iq3xs|bartowski/Qwen_Qwen3-235B-A22B-Instruct-2507-GGUF|IQ3_XS'
  'qwen3-235b-iq3m|bartowski/Qwen_Qwen3-235B-A22B-Instruct-2507-GGUF|IQ3_M'
  'qwen3-235b-thinking-iq2m|bartowski/Qwen_Qwen3-235B-A22B-Thinking-2507-GGUF|IQ2_M'
)

resolve() {
  python3 - "$1" "$2" <<'PY'
import json, sys, urllib.request
repo, quant = sys.argv[1:3]
req = urllib.request.Request(
    'https://huggingface.co/api/models/' + repo,
    headers={'User-Agent':'strix-halo-guide/1.0'})
with urllib.request.urlopen(req, timeout=60) as r:
    data = json.load(r)
files = [x.get('rfilename','') for x in data.get('siblings',[])
         if x.get('rfilename','').lower().endswith('.gguf')]
matches = [n for n in files if any(d == quant or d.endswith('-'+quant)
           for d in n.split('/')[:-1])]
if not matches:
    matches = [n for n in files if n.rsplit('/',1)[-1][:-5].endswith('-'+quant)]
if not matches:
    needle='-'+quant+'-'
    matches=[n for n in files if needle in n.rsplit('/',1)[-1]]
if not matches:
    raise SystemExit(f'No {quant} GGUF found in {repo}')
print('\n'.join(sorted(matches)))
PY
}

if [[ "${1:-}" == '--list' ]]; then
  printf '%-28s %-10s %s\n' MODEL QUANT REPOSITORY
  for e in "${MODELS[@]}"; do IFS='|' read -r id repo quant <<<"$e"; printf '%-28s %-10s %s\n' "$id" "$quant" "$repo"; done
  exit 0
fi

for e in "${MODELS[@]}"; do
  IFS='|' read -r id repo quant <<<"$e"
  target="$MODEL_DIR/$id"
  mkdir -p "$target"
  echo "== $id ($quant) =="
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    file="$target/$(basename "$remote")"
    if [[ -s "$file" ]]; then
      echo "[skip] $file"
      continue
    fi
    url="https://huggingface.co/${repo}/resolve/main/${remote}?download=true"
    wget --continue --show-progress --timeout=60 --read-timeout=60 --tries=20 \
      -O "$file.part" "$url"
    mv "$file.part" "$file"
  done < <(resolve "$repo" "$quant")
done
