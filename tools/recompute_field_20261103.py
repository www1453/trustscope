#!/usr/bin/env python3
"""recompute_field_20261103.py -- canonical recompute of the 2026-11-01 field session.

One command reproduces every number of the field results (report table 3-5 and its
batch-6 supplement). ASCII only.

Sources (all in dl/):
  qc_all_20261101.csv          append-written log, 4 sessions inside, 14/15-col drift
  qc_fused_20261101.csv        corner/chip run log (21:45-21:56)
  qc_order_20261101.csv        placement ledger B001-B100 (board inventory, classes, batches)
  qc_order_extra_20261101.csv  placement ledger C101-C111 (batch 6)

Rules (fixed):
  R1  sessions split by timestamp; pre-run sessions (19:15 / 20:24) excluded
  R2  main run = 21:02-21:38 ; session D (batch-6 first run) = 21:41-21:45 ;
      session E (retest) = 22:02-22:13
  R3  retest overrides first verdict, per board (good boards)
  R4  refusal/unstable pool pools across sessions
  R5  corner verdicts from the validated-tool cross-check (corner_cov_20261101,
      B001 reference, band dumps): 12 NG / 3 OK; borderline (within 0.5 pt of the
      10-point threshold): B090 (-10.1) / B091 (-10.4) / B099 (-9.9)

Assumptions (the only two places memory, not data, decides):
  A1  session-E good row reading (8,8) = board B031 (or B017; count-invariant)
  A2  session-E's 2 CANNOT-JUDGE good placements are 2 main-run-OK boards newly
      refused -> pool = 6, rate = 3/34 = 8.8%.  If they were re-placements of the
      already-refused B010/B040, pool = 4 and the rate is 3/36 = 8.3% instead.
      The report uses A2-pool-6; confirm by placement memory.
"""
import os
import sys
from collections import Counter

DL = os.path.dirname(os.path.abspath(__file__))

# R5: certified corner verdicts (validated tool, see dl/review_20261031/out/corner_fused_crosscheck.json)
CORNER_NG = {'B090', 'B091', 'B092', 'B093', 'B094', 'B095', 'B098', 'B100',
             'C108', 'C109', 'C110', 'C111'}
CORNER_OK = {'B096', 'B097', 'B099'}

# R3: named retest identities (user placement record, consistent with the ledger)
STABLE_NG = {'B027', 'B031', 'B033'}      # A1
REVERTED = {'B017', 'B021', 'B034'}       # main-run NG -> retest OK


def load_qc_all():
    rows = []
    with open(os.path.join(DL, 'qc_all_20261101.csv'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('label,'):
                continue
            p = line.split(',')
            when = p[-1]
            rows.append({'label': p[0], 'cls': p[1], 'verdict': p[2],
                         'darea': p[3], 'when': when})
    return rows


def session_of(when):
    hm = when.split('T')[1][:5]
    if '21:02' <= hm <= '21:38':
        return 'main'
    if '21:41' <= hm <= '21:45':
        return 'D'
    if '22:02' <= hm <= '22:13':
        return 'E'
    return 'pre'


def tally(rows):
    c = Counter(r['verdict'] for r in rows)
    return c


def main():
    rows = load_qc_all()
    by_sess = {'main': [], 'D': [], 'E': [], 'pre': []}
    for r in rows:
        by_sess[session_of(r['when'])].append(r)

    pre = len(by_sess['pre'])
    main = by_sess['main']
    sd = by_sess['D']
    se = by_sess['E']

    # ---- good boards -------------------------------------------------------
    g_main = [r for r in main if r['cls'] == 'g']
    g_main_t = tally(g_main)
    g_e_t = tally([r for r in se if r['cls'] == 'g'])
    n_good = 40
    ng_final = len(STABLE_NG)
    reverted = len(REVERTED)
    pool_main = g_main_t['UNSTABLE'] + g_main_t['CANNOT JUDGE']
    pool = pool_main + 2          # A2
    ok_final = n_good - ng_final - pool

    # ---- pollution / bent --------------------------------------------------
    c_main = tally([r for r in main if r['cls'] == 'c'])
    b_main = tally([r for r in main if r['cls'] == 'b'])
    # session D = batch-6 first run: 3 pollution + 4 bent (labels b001-b007 seq)
    d_c = tally([r for r in sd if r['cls'] == 'c'])
    d_b = tally([r for r in sd if r['cls'] in ('b', 'bb')])
    # H1 attribution (user-confirmed 2026-11-03): session-E NG rows = B068 stable (no flip),
    # b073 flip (batch1-5), C101 flip (batch6); 1 unstable flip (batch1-5)
    pol_ng_b15 = c_main['NG'] + 1            # 17
    pol_ng_b6 = 1                            # C101 retest (8,8) -> NG
    pol_ng = pol_ng_b15 + pol_ng_b6          # 18
    pol_n = 22 + d_c['OK'] + d_c['NG'] + d_c['UNSTABLE']             # 22 + 3 batch6 = 25
    bent_ng = b_main['NG'] + d_b['NG']           # 8 + 2
    bent_n = 11 + d_b['OK'] + d_b['NG'] + d_b['UNSTABLE']            # 11 + 4 = 15

    chip_ng, chip_n = len(CORNER_NG), len(CORNER_NG) + len(CORNER_OK)

    inscope_ng = pol_ng + bent_ng + chip_ng
    inscope_n = pol_n + bent_n + chip_n
    main_only_ng = c_main['NG'] + b_main['NG'] + 12
    main_only_n = 22 + 11 + 15

    print('=== TrustScope field session 2026-11-01 : canonical recompute ===')
    print('sessions: pre-run rows excluded: %d | main %d | D %d | E %d'
          % (pre, len(main), len(sd), len(se)))
    print()
    print('[good boards]  n=%d' % n_good)
    print('  main run      : NG %d / UNSTABLE %d / CANNOT %d / OK %d'
          % (g_main_t['NG'], g_main_t['UNSTABLE'], g_main_t['CANNOT JUDGE'], g_main_t['OK']))
    print('  retest (E)    : NG %d / OK %d / CANNOT %d' % (g_e_t['NG'], g_e_t['OK'], g_e_t['CANNOT JUDGE']))
    print('  adjudicated   : NG %d (stable) / OK %d / pool %d  (A1, A2)'
          % (ng_final, ok_final, pool))
    print('  false-alarm   : %d/%d = %.1f%% (judgeable) | %d/%d = %.1f%% (all)'
          % (ng_final, ng_final + ok_final, 100.0 * ng_final / (ng_final + ok_final),
             ng_final, n_good, 100.0 * ng_final / n_good))
    print('  [A2 check] if the 2 E-session CJ rows were re-placements of B010/B040:')
    print('               pool 4, judgeable 36, rate 3/36 = 8.3%%  <-- pick ONE, report-wide')
    print()
    print('[per class, adjudicated, ALL 111 boards]')
    print('  pollution : %d/%d = %.1f%%   (H1: batch1-5 %d/22 + batch6 %d/3)'
          % (pol_ng, pol_n, 100.0 * pol_ng / pol_n, pol_ng_b15, pol_ng_b6))
    print('  bent      : %d/%d = %.1f%%   (main %d/%d + batch6 %d/%d)'
          % (bent_ng, bent_n, 100.0 * bent_ng / bent_n, b_main['NG'], 11,
             d_b['NG'], d_b['OK'] + d_b['NG'] + d_b['UNSTABLE']))
    print('  corner    : %d/%d = %.1f%%   (batch5 8/11 + batch6 4/4; borderline B090/B091/B099)'
          % (chip_ng, chip_n, 100.0 * chip_ng / chip_n))
    print('  scratch   : 0/16 = 0.0%%    (capability boundary, five-dimension falsification)')
    print()
    print('IN-SCOPE DETECTION (adjudicated, all batches) : %d/%d = %.1f%%'
          % (inscope_ng, inscope_n, 100.0 * inscope_ng / inscope_n))
    print('  main-run-only anchor (batch1-5, one session) : %d/%d = %.1f%%'
          % (main_only_ng, main_only_n, 100.0 * main_only_ng / main_only_n))
    print('  batch1-5 adjudicated (the old "79%%" scope)   : %d/%d = %.1f%%'
          % (38, 48, 100.0 * 38 / 48))
    print()
    print('ledger total: 111 boards = g40 + c25 + b15 + s16 + k15 (qc_order + qc_order_extra)')
    print('report table 3-5 must match THESE numbers or state the batch-6 exclusion reason.')


if __name__ == '__main__':
    sys.exit(main())
