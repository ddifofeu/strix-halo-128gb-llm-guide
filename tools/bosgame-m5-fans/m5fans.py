#!/usr/bin/env python3
"""Bosgame M5 fan interface. Uses ec_su_axb35 sysfs only."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

ROOT = Path('/sys/class/ec_su_axb35')
NAMES = {'fan1': 'CPU fan 1', 'fan2': 'CPU fan 2', 'fan3': 'System fan'}
PROFILES = {'balanced': ([0, 40, 60, 72, 82], [0, 35, 55, 67, 77]),
            'cool': ([0, 30, 50, 65, 75], [0, 25, 45, 60, 70])}

def read(path):
    return path.read_text().strip()

def optional(path):
    try:
        return read(path)
    except OSError:
        return 'unavailable'

def identity():
    return {k: optional(Path('/sys/class/dmi/id') / k) for k in
            ('sys_vendor', 'product_name', 'board_vendor', 'board_name', 'bios_version')}

def check():
    if not ROOT.is_dir():
        raise RuntimeError('Driver absent. Run diagnose, then follow README installation.')
    d = identity()
    text = ' '.join(d.values()).upper()
    if 'AXB35' not in text and d['product_name'].upper() != 'M5' and not ('BOSGAME' in text and 'M5' in text):
        raise RuntimeError('Unrecognized board identity; no writes made. Share diagnose output.')

def fans(target):
    selected = list(NAMES) if target == 'all' else [target]
    for name in selected:
        if not (ROOT / name).is_dir():
            raise RuntimeError(f'{name} is not exposed by the driver; no settings applied.')
    return selected

def write(name, key, value):
    path = ROOT / name / key
    with path.open('w') as f:
        f.write(str(value) + '\n')
    if read(path) != str(value):
        raise RuntimeError(f'Readback mismatch: {name}/{key}')

def auto(selected):
    errors = []
    for name in selected:
        try:
            write(name, 'mode', 'auto')
        except Exception as exc:
            errors.append(f'{name}: {exc}')
    if errors:
        raise RuntimeError('Auto restore incomplete: ' + '; '.join(errors))

def temperatures():
    values = {'EC CPU': float(read(ROOT / 'temp1/temp'))}
    for hw in Path('/sys/class/hwmon').glob('hwmon*'):
        chip = optional(hw / 'name')
        if chip in ('amdgpu', 'k10temp'):
            for p in hw.glob('temp*_input'):
                values[f'{chip}/{p.stem}'] = float(read(p)) / 1000
    if any(not 0 < v < 125 for v in values.values()):
        raise RuntimeError('Invalid temperature reading')
    return values

def snapshot():
    return {'identity': identity(), 'kernel': platform.release(), 'driver_present': ROOT.is_dir(),
            'ec_temperature_C': optional(ROOT / 'temp1/temp'),
            'fans': {n: {k: optional(ROOT / n / k) for k in
                      ('rpm', 'mode', 'level', 'rampup_curve', 'rampdown_curve')}
                     for n in NAMES if (ROOT / n).is_dir()}}

def apply_profile(selected, profile):
    up, down = PROFILES[profile]
    try:
        for n in selected:
            write(n, 'mode', 'auto')
            write(n, 'rampup_curve', ','.join(map(str, up)))
            write(n, 'rampdown_curve', ','.join(map(str, down)))
            write(n, 'mode', 'curve')
    except Exception:
        auto(selected)
        raise

def manual(selected, percent, seconds):
    if percent not in (40, 60, 80, 100) or not 1 <= seconds <= 300:
        raise ValueError('Manual: 40/60/80/100%, duration 1–300 seconds')
    def stop(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    deadline = time.monotonic() + seconds
    try:
        while time.monotonic() < deadline:
            try:
                temp = max(temperatures().values())
                level = 5 if temp >= 80 else percent // 20
            except Exception:
                for n in selected:
                    write(n, 'mode', 'fixed')
                    write(n, 'level', 5)
                raise RuntimeError('Temperature unavailable; aborting manual control.')
            for n in selected:
                write(n, 'mode', 'fixed')
                write(n, 'level', level)
            print(f'{temp:.1f} C | requested {percent}% | applied {level*20}%', flush=True)
            time.sleep(1)
    finally:
        auto(selected)
        print('Selected fans returned to firmware auto.', flush=True)

def gui():
    import tkinter as tk
    from tkinter import ttk, messagebox
    win = tk.Tk()
    win.title('Bosgame M5 · Fan Control')
    win.geometry('760x460')
    win.option_add('*Font', 'Sans 12')
    frame = ttk.Frame(win, padding=20); frame.pack(fill='both', expand=True)
    ttk.Label(frame, text='Bosgame M5 · three-channel fan control', font=('Sans', 18, 'bold')).pack(anchor='w')
    status = tk.StringVar()
    ttk.Label(frame, textvariable=status, justify='left').pack(anchor='w', pady=20)
    target = tk.StringVar(value='all')
    ttk.Combobox(frame, textvariable=target, values=['all', *NAMES], state='readonly').pack(anchor='w')
    child = [None]
    log = Path('/tmp') / f'm5fans-{os.getpid()}.log'
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    stream = os.fdopen(fd, 'w')
    def run(args):
        if child[0] and child[0].poll() is None:
            messagebox.showinfo('Manual test active', 'Stop the current operation first.'); return
        child[0] = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), *args,
                                    '--fan', target.get()], stdout=stream, stderr=stream)
    bar = ttk.Frame(frame); bar.pack(anchor='w', pady=12)
    for label, args in [('Firmware auto', ['auto']), ('Balanced curve', ['profile', 'balanced']),
                        ('Cool curve', ['profile', 'cool'])]:
        ttk.Button(bar, text=label, command=lambda a=args: run(a)).pack(side='left', padx=3)
    row = ttk.Frame(frame); row.pack(anchor='w', pady=8)
    pct = tk.StringVar(value='100')
    ttk.Combobox(row, textvariable=pct, values=['40','60','80','100'], width=6, state='readonly').pack(side='left')
    ttk.Button(row, text='Test % for 60 seconds', command=lambda: run(['manual', pct.get(), '--seconds', '60'])).pack(side='left', padx=8)
    def stop():
        if child[0] and child[0].poll() is None: child[0].terminate()
    ttk.Button(row, text='Stop test', command=stop).pack(side='left')
    ttk.Label(frame, text='Curves remain active after closing. Manual tests restore firmware auto.\n80 °C override: manual tests request 100%. No power-limit changes.', wraplength=700).pack(anchor='w', pady=12)
    def refresh():
        s = snapshot()
        lines = [f"EC CPU: {s['ec_temperature_C']} °C"]
        for n, d in s['fans'].items():
            lines.append(f"{NAMES[n]} ({n})   {d['rpm']} RPM   mode: {d['mode']}   level: {d['level']}/5")
        if not s['driver_present']: lines.append('Driver missing — follow README installation.')
        status.set('\n'.join(lines))
        if child[0] and child[0].poll() is not None:
            if child[0].returncode: messagebox.showerror('Operation failed', log.read_text()[-3000:])
            child[0] = None
        win.after(1500, refresh)
    def close():
        stop()
        if child[0]: child[0].wait(timeout=10)
        stream.close(); log.unlink(missing_ok=True); win.destroy()
    win.protocol('WM_DELETE_WINDOW', close)
    refresh(); win.mainloop()

def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    for cmd in ('diagnose','status','gui'): sub.add_parser(cmd)
    for cmd in ('auto','profile','manual'):
        c = sub.add_parser(cmd); c.add_argument('--fan', choices=['all', *NAMES], default='all')
        if cmd == 'profile': c.add_argument('profile', choices=PROFILES)
        if cmd == 'manual':
            c.add_argument('percent', type=int, choices=[40,60,80,100])
            c.add_argument('--seconds', type=int, default=60)
    a = p.parse_args()
    if a.cmd in ('diagnose','status'):
        print(json.dumps(snapshot(), indent=2)); return
    if a.cmd == 'gui': gui(); return
    if os.geteuid() != 0: raise RuntimeError('Use sudo for fan changes.')
    check()
    lockfd = os.open('/run/m5fans.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lockfd, 'w') as lock:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise RuntimeError('Another m5fans operation is active.')
        selected = fans(a.fan)
        if a.cmd == 'auto': auto(selected)
        elif a.cmd == 'profile': apply_profile(selected, a.profile)
        else: manual(selected, a.percent, a.seconds)

if __name__ == '__main__':
    try: main()
    except KeyboardInterrupt: pass
    except Exception as exc:
        print(f'ERROR: {exc}', file=sys.stderr); sys.exit(1)
