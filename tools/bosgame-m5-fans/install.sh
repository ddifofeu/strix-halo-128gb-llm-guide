#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

DRIVER_REPO="https://github.com/cmetz/ec-su_axb35-linux.git"
DRIVER_COMMIT="f62c2c228959a08683273a26ef3afd8991e69f6d"

if (( EUID == 0 )); then
  echo 'Run bash install.sh as your ordinary user; sudo is requested only for installation.' >&2
  exit 1
fi

for cmd in python3 git make modinfo; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd" >&2
    echo 'Ubuntu: sudo apt install python3 python3-tk build-essential git kmod "linux-headers-$(uname -r)"' >&2
    exit 1
  }
done

python3 - <<'PY'
import m5fans
d = m5fans.identity()
text = ' '.join(d.values()).upper()
if not ('AXB35' in text or d['product_name'].upper() == 'M5' or ('BOSGAME' in text and 'M5' in text)):
    raise SystemExit('Unrecognized board. Run python3 m5fans.py diagnose and review the output.')
print('Detected:', d)
PY

if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
  echo 'Missing headers for the running kernel.' >&2
  echo 'Install: sudo apt install "linux-headers-$(uname -r)"' >&2
  exit 1
fi

MAKE_CC=()
KERNEL_GCC_MAJOR=$(
  grep -oE 'gcc[^0-9]*[0-9]+\.[0-9]+' /proc/version 2>/dev/null |
  grep -oE '[0-9]+' | head -n1 || true
)
if [[ -n "$KERNEL_GCC_MAJOR" ]]; then
  KERNEL_GCC="gcc-$KERNEL_GCC_MAJOR"
  if command -v "$KERNEL_GCC" >/dev/null 2>&1; then
    MAKE_CC=("CC=$KERNEL_GCC")
    echo "Using kernel compiler family: $KERNEL_GCC"
  else
    echo "The running kernel reports GCC $KERNEL_GCC_MAJOR, but $KERNEL_GCC is not installed." >&2
    echo "Install the matching compiler, then rerun this installer." >&2
    echo "For the validated Ubuntu 24.04 + Linux 6.18.7 setup this was gcc-15." >&2
    exit 1
  fi
fi

if [[ -d /sys/class/ec_su_axb35 ]]; then
  echo 'ec_su_axb35 is already loaded; retaining the existing driver and installing the frontend only.'
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "Fetching ec_su_axb35 at pinned commit $DRIVER_COMMIT"
  git clone -q "$DRIVER_REPO" "$tmp/ec-su_axb35-linux"
  git -C "$tmp/ec-su_axb35-linux" checkout -q --detach "$DRIVER_COMMIT"
  make -C "$tmp/ec-su_axb35-linux" "${MAKE_CC[@]}"
  sudo make -C "$tmp/ec-su_axb35-linux" "${MAKE_CC[@]}" modules_install
  sudo depmod -a
  if ! sudo modprobe ec_su_axb35; then
    echo 'Module did not load. Check Secure Boot and kernel logs; do not force-load it.' >&2
    exit 1
  fi
fi

sudo install -m 0755 m5fans.py /usr/local/bin/m5fans
echo 'Installed /usr/local/bin/m5fans. No boot service or custom fan profile has been enabled.'
python3 m5fans.py diagnose
