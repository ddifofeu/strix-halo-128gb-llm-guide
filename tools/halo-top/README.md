# halo-top — Strix Halo telemetry monitor

**halo-top** is a low-overhead terminal monitor for AMD Strix Halo / Radeon 8060S systems using upstream **amdgpu**. It combines GPU clocks/activity, estimated DRAM bandwidth, thermals/power, GTT/UMA, memory pressure, THP coverage, accelerator processes, optional Bosgame M5 EC fan telemetry, CSV/JSONL logging and a small benchmark-summary mode.

The DRAM bandwidth value is an **estimate**, not a hardware byte counter. The current estimator scales the theoretical 256-bit LPDDR bandwidth by GPU busy %. Use it for relative saturation/bottleneck hints, not as a substitute for a controlled bandwidth benchmark such as gfx1151_peak.

## Install on Ubuntu 24.04+

~~~bash
sudo apt update
sudo apt install python3 procps ncurses-bin dmidecode
cd tools/halo-top
bash install.sh
~~~

Run as your normal user:

~~~bash
halo-top
~~~

Useful modes:

~~~bash
halo-top --help
halo-top --log ~/halo.csv
halo-top --jsonl ~/halo.jsonl
halo-top --benchmark 60
halo-top --rate 2
~~~

Interactive keys: **q** quit, **r** reset history/peaks, **m** add a marker, **d** diagnostics, **+/-** change sampling interval.

### Memory-speed detection

halo-top first infers configured memory data rate from the highest exposed **pp_dpm_mclk** state (MCLK × 8 on the validated Strix Halo platform), then tries dmidecode, and finally falls back to 8000 MT/s. Override explicitly when needed:

~~~bash
HALO_MEM_MT_S=7500 halo-top
~~~

The source used for the displayed memory speed is shown in the header.

### Bosgame M5 EC telemetry

If **/sys/class/ec_su_axb35** exists, halo-top also reads the three fan channels and EC temperature. It does **not** write fan settings. Install the separate **bosgame-m5-fans** tool if you intentionally want fan control.

The physical fan-channel mapping is not treated as manufacturer-confirmed; the monitor therefore labels them **fan1**, **fan2**, and **fan3**.

## Remove

~~~bash
sudo rm /usr/local/bin/halo-top
~~~

## Validation

The packaged script is syntax-checked with bash -n. The Bosgame M5 baseline was exercised on AXB35-02 / BIOS 1.07 with Linux 6.18.7 and upstream amdgpu. Not all telemetry nodes exist on every kernel/firmware combination; unavailable values are treated as optional where possible.
