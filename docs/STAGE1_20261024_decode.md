# Stage 1 (2026-10-24) — the two-bit capture index: implemented, measured, NOT shipped

**Result in one line: the fix-3b edge wait is still what selects the capture store. The
two-bit decode from the 2026-10-24 bitstream is implemented, instrumented and selectable,
but it is DISABLED because the index-independent row detector contradicted itself on it
(0.4% torn in one 25 s run, 59% in the next, same code path), while the edge wait measured
0.0-0.6% in four windows across two runs. A selection that reads a store while it is being
written corrupts every later stage, so it does not ship on a measurement that will not
repeat.**

The task's own gate was "verify the mapping FIRST with the existing known-answer probe; if
it does not match, STOP and report." It does not match reproducibly, so this stage stops
there and reports, and the instrumentation is left in place to make the next attempt cheap.

## What was built (`ps_ui/main.c`)

| line | item |
|---|---|
| 192 | `CAP_WR1BIT`, `MB_CAP_MSB` (178, the runtime bit selector) and the boot default |
| 545 | `cap_pair_note()` — the liveness check: the decode is enabled only after all four `(g1,g0)` pairs have been OBSERVED, so an old bitstream (whose second bit never changes) degrades to the edge wait instead of reading a plausible wrong index |
| 683 | `cap_decode_now()` — Gray-to-binary, `writing = (g1<<1)|(g1^g0)` |
| 740 | `cap_read_index()` — decode path, a bounded freshness wait, and the fix-3b edge wait as the fallback |
| 1290 | `cap_order_probe()` (MB_CMD = 6) now records **both** bits and the decode each event word: `store | g0<<4 | g1<<8 | decode<<12` |
| 1994 | words 172-177: `MB_CAP_G1`, `MB_CAP_PAIRS`, `MB_CAP_DEC`, `MB_CAP_DECN`, `MB_CAP_WAITN`, `MB_CAP_WORD`; `MB_CAP_WRIDX` (372) publishes the decoded index again |

## The known-answer probe says the mapping is not reproducible

`ps_fft_dual/st1_probe_rep_20261024.tcl` runs the canary probe six times. The canary is
written to row 0 of all four stores and polled at ~370 kHz; the store whose canary dies is
the store whose write just started, and the pair `(g1,g0)` is read at that instant. In
store order 0,1,2,3:

| run | `g0` (bit 4) | `g1` (bit 15) |
|---|---|---|
| 0 | 0,1,1,0 | 1,1,0,1 |
| 1 | 0,1,1,0 | 1,0,1,1 |
| 2 | 0,1,1,0 | 1,1,0,0 |
| 3 | 0,1,1,0 | 1,1,0,0 |
| 4 | 0,1,1,0 | 0,0,1,1 |
| 5 | 0,1,1,0 | 0,0,1,1 |

**`g0` is a perfect function of the store in all six runs** — the Gray LSB, exactly as FIX3B
measured. **`g1` is not**: it is the correct Gray MSB (`0,0,1,1`) in runs 4 and 5, its
inverse in runs 2 and 3, and unreproducible in runs 0 and 1. A signal that is a function of
the write store cannot do that. Raw log: `dl/st1_probe_rep_20261024.log`.

## The row detector was then used as the arbiter, and it also disagrees with itself

The row detector (`MB_TEAR_ROW/N`, 383/384) is independent of the index: it compares eight
row sums of the store before and after the render, so a store that is being written changes
and a completed one does not. `ps_fft_dual/st1_bit_sweep_20261024.tcl` sweeps every
candidate bit as `frame_ptr_out[1]` (host word 178), 9 s per window:

| bit used as `g1` | torn / renders | rate |
|---|---|---|
| 0 = decode off, edge wait (control) | 0 / 58 | **0.0%** |
| 9 | 0 / 82 | **0.0%** |
| 10 (the BD script's own `In10`) | 40 / 110 | 36.4% |
| 11 | 38 / 95 | 40.0% |
| 12 | 42 / 83 | 50.6% |
| 13 | 41 / 82 | 50.0% |
| 14 | 40 / 83 | 48.2% |
| 15 (the brief's bit) | 25 / 79 | 31.6% |
| 0 again (control) | 0 / 58 | 0.0% |

That looked like a clean answer — the appended port is at bit 9 — so it was confirmed over
25 s windows:

| run | mode | torn / renders | rate | fps |
|---|---|---|---|---|
| 1 | edge wait | 1 / 159 | 0.6% | 6.36 |
| 1 | bit 9 | 1 / 229 | **0.4%** | 9.16 |
| 1 | edge wait | 0 / 160 | 0.0% | 6.36 |
| 1 | bit 9 | 3 / 231 | **1.3%** | 9.24 |
| 2 | edge wait | 0 / 159 | 0.0% | 6.36 |
| 2 | bit 9 | 131 / 222 | **59.0%** | 8.88 |
| 2 | edge wait | 0 / 159 | 0.0% | 6.36 |
| 2 | bit 9 | 133 / 222 | **59.9%** | 8.88 |

Runs 1 and 2 are the same code path, the same 25 s windows and the same host writes; only
the boot default differed (15 in run 1, 9 in run 2), which changes what the decoder did
before the script's first write. 0.4% and 59.0% cannot both describe one mapping. Logs:
`dl/st1_confirm_20261024.log`, `dl/st1_confirm2_20261024.log`, `dl/st1_bit_sweep_20261024.log`.

**What that means: bit 9 is not reliably the index either.** Something other than the bit
number is changing between runs — most plausibly that the second bit, whatever it is, is not
a stable per-store function at all, and a 27.2 ms-period signal read by a ~90-135 ms loop
aliases: a selection that is safe at one loop phase is not at another. That is a hypothesis,
not a measurement, and it is listed as such below.

## What IS measured and worth keeping

1. **The edge wait is not what costs the frames — the wait itself is.** With the decode
   enabled and no freshness wait (bit 15), the loop rose to **11.3 fps** against 6.4 for the
   edge wait, i.e. the 40 ms the fix-3b wait costs is confirmed (matches dl/FIX3B's 82 ->
   136 ms). The read window, however, is longer than the margin the decode leaves:
2. **The read window is ~65 ms**, longer than the 54.4 ms that the decode's worst case
   leaves. Measured: the pure decode tore **36%/39%** (43/120, 47/120) against **2.9%** for
   the edge-synchronised selection and **65%/69%** for the deliberate positive control
   (`dl/st1_tear_20261024.log`). So a freshness gate is required on top of any decode, and
   with it the best measured pair was bit 9's 0.4-1.3% at 9.2 fps — which did not reproduce.
3. **The positive control still works**: `MB_FP_INVERT = 1` (the store being written) reads
   65-78% torn, so the detector can see a written store.
4. **A good part still reads PASS** on the shipped build: `cells = 0`, `MB_DIFF_VERDICT = 0`,
   `MB_REG_STATE = 1`, angle 0.00 deg, dx 0.00 px, dy 0.00 px, scale 1.0000 (`MB_REG_MODE` =
   2, held), and the tear detector reads 0/160 over 25 s at 6.40 fps.

## Acceptance, item by item

| the task's acceptance | result |
|---|---|
| the probe confirms the mapping | **NO** — `g1` is not a function of the store (6 runs, 3 different patterns) |
| the row tear detector stays low on a static scene | **YES as shipped** (0/160, 0.0%, 25 s); it is also low at bit 9 sometimes, which is the problem |
| fps over >= 2 s returns to ~11-12 | **NO** — 11.3 fps is reachable only with the decode that tears 36%; the shipped selection runs at 6.40 fps |
| a good part still reads PASS | **YES** — cells 0, verdict 0, registration unchanged |

## What must happen next, in order

1. **Read the block design** (not rebuild it): `vtc_probe_concat` `CONFIG.NUM_PORTS`, which
   net feeds `In<k>`, and `vtc_probe_concat_dout`'s width. That names the bit. No behaviour
   measurement can, because the probe word is a concatenation of many signals and this
   firmware samples it once per ~90 ms loop, which aliases a 27.2 ms signal. The command is
   `ps_fft_dual/bd_inspect_1024.tcl` (read-only; it needs the Vivado project, which is not in
   this repository).
2. **Sample the probe word at >= 5 kHz from the CPU, not from the host.** A 100-line
   `MB_CMD` that polls `0x41200008` in a tight loop for ~120 ms and records every change
   (word, timestamp) would settle both "is the pair a Gray counter" and "which bits move at
   27.2 ms / 54.4 ms / 109 ms". That is the experiment this stage should have had and did
   not: the host-side sampling used here is far too slow to resolve the signal.
3. Only then decide whether to enable the decode. If the true MSB is found, the freshness
   gate in `cap_read_index()` must stay, because the read window (~65 ms) is longer than the
   margin a 27.2 ms-old store leaves (54.4 ms) — that part is independent of which bit is
   right.

## Not verified, stated plainly

* Whether the appended concat port is at bit 9, 10 or 15. The evidence is contradictory.
* Whether `s2mm_frame_ptr_out` is a Gray counter at all. Bit 4 behaves as a Gray LSB in all
  six probe runs, which is a property of the signal, not of the assumption.
* The physical scene during these runs was not controlled; two windows in this session had
  hundreds of differing cells from something moving through the field of view. The tear
  detector does not depend on the scene (a static and a moving scene both show a rewrite),
  so the A/B stands, but the operator should re-run the sweep on a still bench.
