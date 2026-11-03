#!/usr/bin/env python3
"""qc_run_20261102.py -- one command, many boards: move each in, wait, judge, record.

WHY
    The per-board cycle was three tools and a decision about which to run.  This is one command that
    runs a whole batch: for each board it asks you to place it at the far left, moves it in with
    belt_auto (the timed mover, measured stops 88.0 and 79.0 cells -- chosen over the photoeye
    trigger, whose ten-cell error is enough for the registration to lock onto the wrong periodic
    peak on this board's artwork), waits for the station to be judgeable, reads the verdict and
    appends one row.

WHAT IT WILL NOT DO
    It will not turn a refusal into a pass.  MB_DIFF_OK != 1 or MB_REG_STATE != 1 prints CANNOT
    JUDGE with the reason, and that row is recorded as a refusal.

USAGE
    python dl\\qc_run_20261102.py --count 20 --cls good
    python dl\\qc_run_20261102.py --count 1 --cls contaminated --no-belt
    python dl\\qc_run_20261102.py --count 89 --class-file dl\\qc_order_20261101.csv

ASCII ONLY.
"""
import argparse
import csv
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XSDB = r'D:\Vitis\Vitis\2023.1\bin\xsdb.bat'

TCL = """
proc RD {a} { set v -1; if {[catch { set v [mrd -force -value $a] }]} { return -1 }; return [expr {$v & 0xFFFFFFFF}] }
proc W {n} { RD [expr {0x10F00000 + $n*4}] }
proc S16 {v} { set x [expr {$v & 0xFFFF}]; return [expr {($x >= 0x8000) ? $x - 0x10000 : $x}] }
connect
for {set i 0} {$i < 40} {incr i} { if {[string match "*Cortex-A9*" [targets]]} { break }; after 500 }
targets -set -filter {name =~ "*Cortex-A9*#0"}
puts [format "Q pts=%d diffok=%d reg=%d refq=%d darea=%d lim=%d clip=%d regwhy=%d dx=%d dy=%d" \
    [W 366] [W 180] [W 232] [W 544] [W 23] [W 564] [W 213] [W 234] [S16 [W 201]] [S16 [W 202]]]
exit 0
"""


def read(timeout=120):
    p = os.path.join(ROOT, 'dl', '_qcrun.tcl')
    with open(p, 'w', encoding='ascii', newline='\n') as f:
        f.write(TCL)
    try:
        r = subprocess.run([XSDB, p], capture_output=True, text=True, errors='replace', timeout=timeout)
    except Exception:                                        # noqa: BLE001
        return None
    for line in (r.stdout or '').splitlines():
        if line.strip().startswith('Q pts='):
            d = {}
            for tok in line.strip()[2:].split():
                k, v = tok.split('=', 1)
                try:
                    d[k] = int(v)
                except ValueError:
                    d[k] = v
            return d
    return None


def one_board(a, cls, idx, total):
    print('\n  ----- board %d of %d  [%s] -----' % (idx, total, cls or '?'))
    if not a.no_belt:
        input('  place it at the far LEFT, then press Enter > ')
        subprocess.run([sys.executable, os.path.join(ROOT, 'dl', 'belt_auto_20261031.py'),
                        '--port', a.port, '--target', str(a.target), '--tol', str(a.tol),
                        '--first-seconds', '2.0'],   # CALIBRATED 2026-11-02: the default one-second
                        # calibration window starts while the board is still clipped at the frame's
                        # left edge, so the measured centre does not move and belt_auto reads
                        # 0.0 cells/s -- measured three times.  Two seconds puts the board far
                        # enough in to measure, and the same board then lands at 73.0 / 72.5 / 81.5.
                       cwd=ROOT, capture_output=True, text=True, errors='replace')
    else:
        input('  place it at the station, then press Enter > ')

    t0 = time.time()
    d = None
    while time.time() - t0 < a.timeout:
        d = read()
        if d and d.get('diffok') == 1 and d.get('reg') == 1:
            break
        time.sleep(1.5)
    if d is None:
        print('  no mailbox -- not measured')
        return None

    if d.get('diffok') != 1 or d.get('reg') != 1:
        v = 'CANNOT JUDGE'
    elif d.get('darea', 0) >= d.get('lim', 8):
        v = 'NG'
    else:
        v = 'OK'
    print('  %-13s darea %d / limit %d   diffok %d   reg %d   refq %d   clip %d   dx %d  dy %d'
          % (v, d.get('darea', -1), d.get('lim', -1), d.get('diffok', -1), d.get('reg', -1),
             d.get('refq', -1), d.get('clip', -1), d.get('dx', 0), d.get('dy', 0)))
    if v == 'CANNOT JUDGE':
        print('  refused: diffok=%s reg=%s regwhy=%s'
              % (d.get('diffok'), d.get('reg'), d.get('regwhy')))
    return (cls, v, d)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--count', type=int, default=1)
    ap.add_argument('--cls', default='')
    ap.add_argument('--class-file', default='', help='a CSV with a cls column; one class per board')
    ap.add_argument('--port', default='COM8')
    ap.add_argument('--target', type=int, default=80)
    ap.add_argument('--tol', type=int, default=20)
    ap.add_argument('--timeout', type=float, default=25.0)
    ap.add_argument('--no-belt', action='store_true')
    a = ap.parse_args()

    classes = []
    if a.class_file:
        rows = list(csv.DictReader(open(a.class_file, encoding='utf-8')))
        classes = [r.get('cls', '') for r in rows]
        a.count = len(classes)
    if not classes:
        classes = [a.cls] * a.count

    print('=' * 72)
    print('INSPECTION RUN -- %d board(s), one command' % a.count)
    print('  a refusal is recorded as a refusal; it is never counted as a pass')
    print('=' * 72)

    out = os.path.join(ROOT, 'dl', 'qc_run_20261102.csv')
    new = not os.path.isfile(out)
    fh = open(out, 'a', newline='', encoding='utf-8')
    w = csv.writer(fh)
    if new:
        w.writerow(['cls', 'verdict', 'darea', 'limit', 'diffok', 'reg', 'refq', 'clip',
                    'dx', 'dy', 'when'])
    results = []
    try:
        for i, cls in enumerate(classes, 1):
            r = one_board(a, cls, i, a.count)
            if r is None:
                continue
            c, v, d = r
            w.writerow([c, v, d.get('darea', -1), d.get('lim', -1), d.get('diffok', -1),
                        d.get('reg', -1), d.get('refq', -1), d.get('clip', -1), d.get('dx', 0),
                        d.get('dy', 0), time.strftime('%Y-%m-%dT%H:%M:%S')])
            fh.flush()
            results.append(r)
    finally:
        fh.close()

    print('\n' + '=' * 72)
    import collections
    tally = collections.Counter((c, v) for c, v, _ in results)
    for cls in sorted(set(c for c, _ in tally)):
        row = {v: n for (c, v), n in tally.items() if c == cls}
        print('  %-14s %s' % (cls or '?', row))
    print('  csv: %s' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
