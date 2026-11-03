# On-demand evidence snapshots + `sweep.py --evidence` (2026-10-27)

Firmware: `ps_ui/main.c` (the EVID block, the comparison tail, the MB_CMD dispatcher).
Host: `dl/host_qc/evidence.py`, `dl/host_qc/sweep.py --evidence`.
Companion to `dl/EVIDENCE_20261026.md`, which documents the NG-triggered snapshot this
change extends.

## 0. What it is, in one paragraph

The NG evidence snapshot could only be armed by the comparison's own NG verdict, so the
only frames it could ever leave behind were frames of parts that had already failed.  A
40-board sweep that measured DAREA for 20 good and 20 defective boards cannot be compared
with a learned anomaly model using those numbers alone: the model needs the images of the
SAME boards.  The snapshot can now be REQUESTED with one host command (`MB_CMD = 21`),
honoured at the firmware's next comparison boundary, and `sweep.py --evidence` requests,
waits for, dumps and VERIFIES one snapshot per recorded board and files it under
`dl/sweep_frames/<session>/<label>/` with the row's identity in `meta.json`.  The firmware
also appends five words to its metadata block so the host can prove the four files are the
snapshot it asked for, not a spliced, stale or mis-addressed picture.

## 1. The command, and why 21 cannot collide

`MB_CMD = 21` is consumed once by the dispatcher at the end of the loop and held in a
request flag until the comparison block can arm it; it is cleared then, so it is one-shot
by construction (the `MB_REFQ_DECL` property, without spending a mailbox index).

The numbers the firmware already answered when this was written, read from the dispatcher's
`if/else if` chain (`main.c`, the `Host-triggered probes (MB_CMD)` block):

| number | what it does | cleared by the firmware? |
|---|---|---|
| 1 | capture-rate probe | yes |
| 2 | stall-localisation benchmark | yes |
| 3 | busy loop | yes |
| 5 | camera-1 rate probe | yes |
| 6 | capture-ring write-order known-answer probe | yes |
| 7 | CNN self-test | yes |
| 8 | display self-test (solid colours) | **no, by design: stays until the host writes 0** |
| 9 | re-take the reference | yes |
| 12 | take the background (empty belt) | yes |
| 13 | classifier known answers | yes |
| 14 | known-answer re-aim | yes |
| 15 | known-answer size stamp into the reference | yes |
| 16 | learn one good unit (tolerance map) | yes |
| 17 | re-derive the reference from REF_BASE | yes |
| 18 | adopt the background already in DDR | yes |
| 19 | empty the tolerance map | yes |
| 20 | run the boot self-test | yes |

4, 10 and 11 are gaps; 21 is the next number above the highest one in use.  Nothing else
in the firmware compares `MB_CMD` against 21, and no host tool writes 21: a repo-wide
search for `MB_CMD = <number>` / `cmd == <number>` over `*.py`, `*.tcl` and `*.md` lists 5,
6, 7, 8, 9, 12..20 and nothing above 20.  `qc_mailbox.py` and `check_words.py` need no
change: no new WORD is defined, so the mailbox map is untouched (394 MB_* definitions, 0
collisions before and after this change).

## 2. The firmware change

Three hunks in `ps_ui/main.c`:

1. **The EVID block.**  `EVID_VER` 2; `SNAP_CMD 21`; `g_evid_req` (the consumed command);
   `evid_arm(why)` returns whether it armed, so the caller knows whether to consume the
   request, and writes `why` straight into the buffer; `evid_copy` computes the five proof
   words and writes metadata indices 24..28 into buffer words 26..30.
2. **The comparison tail.**  After `MB_DIFF_VERDICT` is republished: an NG arms with
   `why = 1`; a pending host request is armed with `why = 2` here (and only here), after the
   comparison has published every word the metadata copies; if both happen at one boundary
   the request rides on the NG snapshot (`why = 3`).
3. **The dispatcher.**  `cmd == SNAP_CMD` sets `g_evid_req` and clears `MB_CMD`.

**A defect in the 2026-10-26 version, found while making snapshots repeatable.**  The host's
ack (`MB_EVID_STATE = 0`) was read only when a snapshot was already pending, and
`evid_arm()` refused while the mirror `g_evid_state` was non-zero.  The mirror was therefore
never cleared after the first snapshot: a second NG could not arm, and `MB_EVID_SEQN` could
never exceed 1.  "A slow host loses later NGs instead of corrupting the one it reads" was
true for the FIRST snapshot per boot only.  The ack is now read at the top of `evid_copy`
on every loop, before the pending test, so the ack is the only thing that releases the slot.
This is a host-visible behaviour change: after this build, an NG whose snapshot the host has
read CAN arm again.  It has not been observed on hardware yet (nothing about this change
has); it is asserted offline and must be proven on the board (section 5).

**OCM cost, and the headroom warning.**  The build is close to the 128 KB limit: before
this change 130,652 of 131,072 bytes were used, after it 131,016 -- **56 bytes free**.  The
five proof words cost 356 bytes net (the new metadata words live in the existing 32-word
buffer; `g_evid_req` is 4 bytes; the frame sum is accumulated inside the existing copy
loop).  **The next change that adds more than 56 bytes of code or `.bss` to `main.c` will
not link**, and it will fail at the worst moment (a build during a board round), so it must
free something first -- there is no spare OCM left to spend.

**If it must be freed (the first person to hit that link failure will need this).**  The
largest `.bss` residents, measured on this build with
`arm-none-eabi-nm --size-sort --print-size --radix=d ps_ui/ps_ui.elf` (301 objects,
12,054 bytes total, against 118,844 of `.text`):

| object | bytes | note |
|---|---|---|
| `img.1` | 4,096 | a function-local `static` (the `.1` is the compiler's), so find it by reading the function that declares it, not by the name |
| `g_dflag` | 3,600 | a per-cell flag grid |
| `g_lut` | 768 | a table |
| `g_part_hist`, `g_bg_hist` | 512 each | 256-bin histograms |
| `g_blob` | 336 | |
| `g_evid_meta` | 96 | this change's metadata array |

The honest options, in the order this project's own incidents recommend:

1. **Move a buffer to DDR.**  `img.1` (4 KB) or `g_dflag` (3.6 KB) are CPU-only scratch --
   nothing DMA touches them -- and the MMU already maps 0x12000000..0x127FFFFF read-write
   for LIVE_MASK / FINE_DEEP / FINE_TOL / the fine accumulators.  The cost is an address
   change, not a new section; verify the chosen address is inside that window in `mmu.c`
   and that it collides with no existing buffer's end.
2. **Share a scratch buffer.**  The project already overlaps PART_CC_TMP between the
   cluster rule and the deep-cell flag grid because the two are never live at the same
   time.  Any new pair with the same lifetime argument is a free 1-4 KB -- but the comment
   must state WHY the lifetimes cannot overlap, because a silent overlap is exactly how
   BASE_MASK_D and FINE_FLAG collided before.
3. **Drop or pack a word** -- only for `.bss` globals.  Packing the snapshot's metadata
   words does NOT free OCM (they already live inside the 128-byte buffer).  Several of the
   301 `.bss` objects are counters from finished experiments; deleting a dead one is
   cheaper than either option above, but it must be PROVEN dead (grep the writers, boot,
   and check that every word the docs promise still publishes).

It is not acceptable to shave the evidence buffer or the fine grids to make room: they are
the measurement.

## 3. Metadata version 2, and what the host checks

| index | word | meaning |
|---|---|---|
| 24 | `why` | 1 = the comparison's own NG, 2 = host request, 3 = both |
| 25 | `cap_kind` | 1 = two-bit decode, just-completed store; 2 = edge-wait fallback, just-completed store; 3 = neither proven |
| 26 | `mask_fnv` | FNV-1a over the 14,400 copied mask bytes |
| 27 | `frame_sum8` | little-endian word sum of the copied frame, words 0, 8, 16, ... |
| 28 | `tol_exact` | 1 = the tolerance bytes are the ones the comparison applied |

`evidence.coherence_report()` is PURE (bytes and dicts in, report out) and is exercised by
`evidence.py --selftest` one failing check at a time.  A snapshot enters the set only if
every check is True:

| check | rule | what it catches |
|---|---|---|
| `version` | metadata ver == 2 | an older image, whose proof words do not exist |
| `why` | 1, 2 or 3 | a buffer nothing here armed |
| `cap_kind` | 1 or 2 | a copy whose store selection was not the just-completed store (bracket mode, or a selection path that did not prove itself) |
| `handshake` | `MB_EVID_STATE` 1 and `MB_EVID_SEQ` == metadata `diff_n` | the metadata block and the handshake word describing different snapshots |
| `freshness` | `MB_EVID_SEQN` moved past the value read before the request | a buffer left ready by a PREVIOUS board |
| `mask_count` | set cells in `mask.bin` == `MB_PART_PTS_C` | a mask file from another comparison or another board |
| `mask_hash` | FNV-1a of `mask.bin` == `mask_fnv` | a partial or mis-addressed mask dump |
| `fvalid_bound` | nonzero `fine_deep.bin` cells <= `MB_DIFF_FVALID` | fine grids from a different comparison |
| `darea` | largest 8-connected group of `|d| > tolerance` == `MB_DIFF_DAREA`, only when `tol_exact` | grids whose difference data does not reproduce the row's DAREA |
| `frame_sum` | word sum of `frame.bin` == `frame_sum8` | a frame dumped from the wrong address with a plausible length |
| `ref_match` | snapshot `MB_PART_REF` == row `MB_PART_REF` | a snapshot taken after a mid-run reference re-take |
| `judged` | snapshot `MB_DIFF_OK` == 1 | a snapshot taken on a refused comparison |
| `row_order` | snapshot `MB_DIFF_N` >= row `MB_DIFF_N` | a previous board's buffer |

`tol_exact` exists because the judge does not read the tolerance byte directly: it reads
`tol_at(key, scale)`, which scales the learned map by the host's envelope weight.  The DAREA
identity above is exact only when the applied tolerance equals the byte, which is true when
the scale is 256 or when no cell is above the floor (`g_tol_var == 0`, maintained by
`tol_stats()`).  Otherwise the host records `darea` as NOT PROVEN and the frame is refused,
rather than deriving a DAREA the firmware never computed.

## 4. Cost and disk

* Firmware copy: measured 30.7 ms for the 2026-10-26 version; this version adds a 1-in-8
  word sum and a 14,400-byte hash inside the same passes.  Estimated +2-4 ms, i.e. still
  inside the store's ~81 ms safe window.  `MB_EVID_TICKS` reports the real number per
  snapshot and the sweep prints it (`copy_ms` in the frame ledger), so this estimate is not
  what the report will quote after the board run.
* Host, per board: boundary wait 0..~2.2 s (one comparison period; DIFF_EVERY 16 loops at
  ~137 ms), one 32-word metadata read, four `mrd -bin` dumps (2.76 MB + 3 x 14.4 kB, ~7 s at
  the measured ~400 kB/s), and ~1 s of Python checks.  Estimated 10-13 s per board; the
  sweep measures and prints it, and the frame ledger records `wait_s`, `dump_s`, `check_s`,
  `total_s`.
* Disk: 2,808,000 bytes per board (four files) + ~2 kB of `meta.json`; 41 boards ~115 MB.
  `dl/sweep_frames/` is in `.gitignore`; `sweep_<session>_frames.csv` (the ledger, ~200 B
  per row) is tracked.  The gate refuses to start below 300 MB free and stops a board below
  20 MB.

## 5. What must be proven on the board (none of it has been)

Offline proof so far: the firmware compiles and links (4 pre-existing warnings, 0 mailbox
collisions, layout checks pass); `evidence.py --selftest` passes (FNV-1a against published
vectors, the group rule, every failing check, and `capture()` end-to-end against fake xsdb
I/O including a stale buffer and a rejected dump); `sweep.py --selftest` passes including
`--evidence --sim` and the reference-change stop; `sweep.py --sim --evidence` runs.

On the board, in this order:

1. `MB_FWID0..2` reads `TSC1` + the hash in `ps_ui/build_id.h` (the gate refuses otherwise).
2. A snapshot can be requested on a PASSING comparison: `evidence.py --request` on a clean
   board must print `COHERENT`, with `why = 2`, `cap_kind = 1`, and every check ok.  This is
   the whole point of the change and the NG path proves nothing about it.
3. A SECOND request in the same boot lands and is coherent (`MB_EVID_SEQN` 1 -> 2), which is
   the fix in section 2 observed rather than argued.
4. A request issued while a comparison is in progress does not disturb the comparison: the
   row taken before the request still replies, and the snapshot's `MB_DIFF_N` is at or after
   it.  (The copy runs at the top of a later loop; the comparison is not reading the store
   then.)
5. `copy_ms` from `MB_EVID_TICKS` is <= ~40 ms; if it approaches 81 ms the copy is eating
   the store's safe window and the snapshot must not be trusted.
6. The per-board host cost (wait + dump + checks) is what the run can afford: a 41-board
   run is ~10 minutes of extra wall clock on top of the operator's placement time.
7. `record.py --evidence` still works on an NG (the older path): the metadata grew but
   `decode_meta` accepts a version-2 buffer (it reads 32 words and names all 29 fields).
   Unverified: a live NG with `--evidence` after this build.
8. Unverified by design: a snapshot taken while the part is MOVING (the firmware copies the
   first completed store after the comparison; a board removed in that window would give a
   coherent frame of the belt).  The sweep blocks the operator until the frame is filed, so
   a run cannot produce it, but the tool alone does not know the operator moved the board.
9. Unverified by design: `cap_kind = 2` (edge-wait fallback).  The station has the two-bit
   decode; the fallback path is kept and reported, not exercised.

## 6. Process note: two agents, one file

While this change was being written, a second agent was editing `ps_ui/main.c` for the
blind-spot diagnostics (words 553..571).  The file grew from 15,044 lines to 15,396 and its
mtime moved twice inside ten minutes, and neither the mailbox map nor `git status` would
have shown the collision if the word allocation had been guessed instead of read:
`dl/mb_free.py` reports 572..639 free, but only as of the instant it runs.  Two mitigations
came out of it: the request is a COMMAND (no index to collide on), and the firmware was
developed, compiled and measured against a COPY of `main.c` in a temp directory, so a
half-written file never had to be built.  Two agents editing one file is the same class of
hazard as two xsdb clients on one cable; the detection method (git status + mtime + line
count) is what made it visible instead of silent.

## 7. Files changed

| file | what |
|---|---|
| `ps_ui/main.c` | EVID block (version 2, `SNAP_CMD`, `evid_arm(why)`, the proof words, the ack fix), the comparison tail, the dispatcher branch |
| `dl/host_qc/evidence.py` | `SNAP_CMD`, the proof helpers, `read_identity`/`expected_identity`, `request_snapshot`/`wait_snapshot`/`ack_snapshot`, `dump_snapshot`, `capture`, `coherence_report`, `--request`, selftest |
| `dl/host_qc/sweep.py` | `--evidence` and its gates, `FrameRecorder`/`FakeFrameRecorder`, the frame ledger, the reference-change stop, selftest |
| `dl/host_qc/README.md` | section 20 |
| `dl/EVIDENCE_SNAPSHOT_20261027.md` | this file |
| `.gitignore` | `dl/sweep_frames/` |
