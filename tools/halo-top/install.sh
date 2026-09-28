#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

for cmd in bash python3 awk ps tput grep sed readlink date; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd" >&2
    echo "Ubuntu: sudo apt install python3 procps ncurses-bin coreutils gawk grep sed" >&2
    exit 1
  }
done

bash -n halo-top
sudo install -m 0755 halo-top /usr/local/bin/halo-top
echo "Installed /usr/local/bin/halo-top"
echo "Run: halo-top"
