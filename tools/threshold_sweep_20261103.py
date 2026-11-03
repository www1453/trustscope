#!/usr/bin/env python3
"""threshold_sweep_20261103.py -- verdict-vs-threshold sweep on the 2026-11-01 main run.

Question answered: what happens to detection and false alarms if the grid-channel
limit moves off 8 (e.g. to 5)?

Scope: main session only (21:02-21:38, 89 placements, one per board, batch 1-5).
Rule: a placement counts NG at threshold t iff its logged darea >= t AND its
8-threshold verdict was stability-verified (OK or NG). UNSTABLE/CANNOT rows keep
their own state at every t (their double-read already disagreed or failed).
The corner channel is independent of this limit (10-point coverage statistic).

ASCII only.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# data/ in the published repo, dl/ in the working tree the script was written in.
DL = next((d for d in (os.path.join(ROOT, 'data'), os.path.join(ROOT, 'dl'), HERE)
           if os.path.isfile(os.path.join(d, 'qc_all_20261101.csv'))), HERE)


def load_main():
    rows = []
    with open(os.path.join(DL, 'qc_all_20261101.csv'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('label,'):
                continue
            p = line.split(',')
            when = p[-1]
            hm = when.split('T')[1][:5]
            if not ('21:02' <= hm <= '21:38'):
                continue
            d = p[3]
            d = int(d) if d.lstrip('-').isdigit() else -1
            rows.append({'cls': p[1], 'verdict': p[2], 'darea': d})
    return rows


def main():
    rows = load_main()
    cls = {'g': [], 'c': [], 'b': [], 's': []}
    for r in rows:
        if r['verdict'] in ('OK', 'NG'):          # stability-verified placements
            cls[r['cls']].append(r['darea'])
        # UNSTABLE / CANNOT rows stay in their own pool at every t
    unstable = sum(1 for r in rows if r['verdict'] in ('UNSTABLE', 'CANNOT JUDGE'))

    print('main run, %d placements (%d stability-verified, %d unstable/cannot)'
          % (len(rows), sum(len(v) for v in cls.values()), unstable))
    print('good boards on stage: %d' % len(cls['g']))
    print()
    hdr = ' t | good FA | pollution | bent | scratch | in-scope det'
    print(hdr)
    print('-' * len(hdr))
    for t in range(4, 11):
        fa = sum(1 for d in cls['g'] if d >= t)
        pc = sum(1 for d in cls['c'] if d >= t)
        bc = sum(1 for d in cls['b'] if d >= t)
        sc = sum(1 for d in cls['s'] if d >= t)
        det = (pc + bc + 12) * 100.0 / 48.0      # corner 12/15 is limit-independent
        print(' %2d |  %d/36 = %4.1f%% | %2d/22 = %4.1f%% | %d/11 = %4.1f%% | %d/16 = %4.1f%% | %2d/48 = %4.1f%%'
              % (t, fa, 100.0 * fa / 36, pc, 100.0 * pc / 22,
                 bc, 100.0 * bc / 11, sc, 100.0 * sc / 16, pc + bc + 12, det))
    print()
    print('adjudicated point (retest-informed): t=8 -> 3/34 = 8.8% judgeable | 3/40 = 7.5% all')
    print('retest covered 10 of 40 good placements: only the t=8 point is retest-adjudicated;')
    print('all other thresholds are SINGLE-MEASUREMENT apparent rates (production-relevant).')
    sc8 = sum(1 for d in cls['s'] if d >= 8)     # scratch column at the operating point
    print('scratch at t=8: %d/16 = %.1f%%' % (sc8, 100.0 * sc8 / 16))
    print('corner channel (independent): 12/15 = 80.0% at any grid limit')
    print('note: tonight good-board floor = 7 (archive floor <= 5): the floor rose')
    print('      with lighting/reference drift, so limits <= 7 sit BELOW the floor.')


if __name__ == '__main__':
    main()
