#!/usr/bin/env python3
"""soak_20261101.py -- launch the overnight soak and read its result back.

    python tools\\soak_20261101.py --start --hours 7
    python tools\\soak_20261101.py --report                 # next morning

The soak records one row every --period-ms through ONE xsdb connection (see
ps_fft_dual\\soak_20261101.tcl).  It is read-only: it never writes a mailbox word, never touches the
sensor and never changes the reference, because a soak that perturbs the thing it measures proves
nothing.

WHAT THE REPORT ANSWERS -- the four reliability numbers the competition's indicator list names:
    连续稳定运行时间   first and last timestamp, row count and sampling period
    判定次数           counts of NG / OK / CANNOT
    异常次数           rows where diffok != 1 or regstate != 1, with the reason codes
    有无重启           any decrease in the frame counter is a restart
plus the darea distribution, so the report can say whether the verdict drifted over the run.

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
TCL = os.path.join(ROOT, 'ps_fft_dual', 'soak_20261101.tcl')
DEFAULT_OUT = os.path.join(ROOT, 'data', 'soak_20261101.csv')


def start(hours, period_ms, out):
    samples = int(hours * 3600 * 1000 / period_ms)
    # READ AS UTF-8 AND STRIP NON-ASCII.  The template carries Chinese comments; xsdb reads a Tcl
    # file as ASCII/GBK, and Python's ascii decoder refuses it outright (measured 2026-11-02:
    # UnicodeDecodeError, byte 0xe8 at offset 485).  Strip rather than replace so the emitted script
    # stays pure ASCII -- the discipline every other Tcl in this repo follows.
    raw = open(TCL, encoding='utf-8', errors='replace').read()
    src = ''.join(ch if ord(ch) < 128 else ' ' for ch in raw)
    run = (src.replace('OUTCSV', out.replace('\\', '/'))
              .replace('SAMPLES', str(samples))
              .replace('PERIODMS', str(period_ms)))
    p = os.path.join(ROOT, 'ps_fft_dual', '_soak_run.tcl')
    open(p, 'w', encoding='ascii', newline='\n').write(run)
    log = os.path.join(ROOT, 'data', 'soak_20261101.log')
    fh = open(log, 'w', encoding='utf-8')
    proc = subprocess.Popen([XSDB, p], stdout=fh, stderr=subprocess.STDOUT)
    print('soak started: %d samples over %.1f h at %d ms  ->  %s' % (samples, hours, period_ms, out))
    print('  pid %d, log %s' % (proc.pid, log))
    print('  leave ONE board on the stage and do not touch the station.')
    print('  read it back tomorrow with:  python dl\\soak_20261101.py --report')
    return 0


def report(out):
    if not os.path.isfile(out):
        print('no soak csv at %s' % out)
        return 2
    rows = list(csv.DictReader(open(out, encoding='utf-8')))
    if not rows:
        print('soak csv is empty')
        return 2

    def num(r, k):
        try:
            return int(float(r.get(k, '') or 0))
        except ValueError:
            return 0

    t = [num(r, 't_ms') for r in rows]
    counts = {}
    for r in rows:
        counts[r['verdict']] = counts.get(r['verdict'], 0) + 1
    bad = sum(1 for r in rows if r['verdict'] == 'CANNOT')
    fr = [num(r, 'frames') for r in rows]
    restarts = sum(1 for a, b in zip(fr, fr[1:]) if b < a)
    dar = sorted(num(r, 'darea') for r in rows)
    dur = (t[-1] - t[0]) / 1000.0 if len(t) > 1 else 0

    print('=' * 70)
    print('SOAK REPORT  %s' % out)
    print('=' * 70)
    print('  rows                : %d' % len(rows))
    print('  duration            : %.2f h  (%.1f s)' % (dur / 3600.0, dur))
    print('  mean sampling period: %.1f s' % (dur / max(1, len(rows) - 1)))
    print()
    for k in ('OK', 'NG', 'CANNOT'):
        print('  %-8s            : %d  (%.1f %%)' % (k, counts.get(k, 0),
                                                    100.0 * counts.get(k, 0) / len(rows)))
    print('  异常次数 (refusals) : %d' % bad)
    print('  重启 (frame counter decreased) : %d' % restarts)
    print()
    if dar:
        print('  darea  min/median/max : %d / %d / %d' % (dar[0], dar[len(dar) // 2], dar[-1]))
    print()
    print('  what this answers: 连续稳定运行时间、判定次数、异常次数、有无重启')
    print('  what it does NOT answer: anything about a board that was not on the stage')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--start', action='store_true')
    ap.add_argument('--report', action='store_true')
    ap.add_argument('--hours', type=float, default=7.0)
    ap.add_argument('--period-ms', type=int, default=2000)
    ap.add_argument('--out', default=DEFAULT_OUT)
    a = ap.parse_args()
    if a.start:
        return start(a.hours, a.period_ms, a.out)
    if a.report:
        return report(a.out)
    print(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main())
