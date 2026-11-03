# A part mask that does not need a static background — 2026-10-29

Status: **built and verified offline. NOTHING FLASHED, nothing touched on the station.**
The station is running the operator's 100-board sweep on the previous build
(`TSC1327CD597`); the work below is source + offline measurement only. The number that
decides whether this ships has **not** been measured — see §6 for exactly what will
measure it.

---

## 0. PREDICTIONS — written before the measurement, and what happened

| | prediction | outcome |
|---|---|---|
| **H1** | a margin scaled by the frame's own level is the fix for the 2026-10-25 lighting failure: the mask moves <15 % where the absolute margin moves >30 % | **PARTLY CONFIRMED.** ±10 % exposure: −3.5…+3.3 % (absolute rule: −45…+31 %). At **+20 %** on the palest frame it **loses 35 %** (603→391, below the 400 floor). That row is reported, not smoothed over — see §5. |
| **H1b** | a margin tied to the score's own spread (`3·MAD`) would be the textbook choice | **REFUTED, as predicted, and the reason is worth keeping:** the spread of a frame that contains the part is partly the *part's own* contrast, so the margin grows with the part and the rule feeds back on itself. Measured: margin 33–39 on the good frames, mask 2599→1544 and 2950→**528** (1.3× the 400 floor). Rejected. |
| **H2** | the empty belt reads <200 clustered cells and does not rise when the belt moves | **CONFIRMED AND BETTERED.** Without the chromaticity gate the empty belt reads 265 cells, and one belt position reaches exactly **400** = `PART_MIN_PTS` — the gate would open. With the gate: **0 at every belt position tested**, worst 0. |
| **H3** | the shipped background rule is what breaks when the belt moves | **NOT REPRODUCED on the still frames available** (see §5.4) — the harness can move the *live* frame but has no stored background that was taken at a different belt position, so it could not show the 646→5825 growth. That control is missing and is listed as unmeasured. |

Everything below is from `dl/PART_MASK_20261029.py`, `dl/joint_rule_20261029.py`,
`dl/mask_chroma_20261029.py` and `dl/fw_mirror_20261029.py` on the board's own dumped
frames. The last of those reproduces the patched firmware's integer arithmetic step by
step and is checked against a published number before it reports anything (§4).

---

## 1. The rule, and why this one

The judged cells are already `live mask ∩ reference mask`, so the belt outside the part
never enters the verdict (main.c:6126, "STAGE 2: ONLY POINTS INSIDE THE PART ARE
SCORED"). **That part of the design is right and is untouched.** What breaks when the
belt moves is the **live** mask, and that is the only thing this change touches.

The live mask is now built by the colour rule, with **two frame-referenced terms**:

```
score(cell)  = mean of 2x2 samples of (G − max(R,B)) at +2,+5        [unchanged]
median       = the frame's own block-score median                     [unchanged]
margin       = clamp_{>=6}( (gsum · 12) / (57,600 · 130) )            [NEW — level]
mask         = score > median + margin, eroded 3x3                   [unchanged]
mask        := mask, then the CHROMATICITY GATE                       [NEW — object]
```

### 1a. Why the level, and not the spread

`score` is a **difference of channels**, so a change in gain scales it. The old margin
was a constant 12 counts, i.e. a fixed amount of *signal*, which under a gain change
stops meaning the same fraction of the picture. The frame's own **mean green** scales
with exactly the same gain, so dividing by it makes the margin scale with the score and
the mask stays put.

`gsum` is accumulated inside `part_score()`, from the four samples it already reads —
**the normalisation costs no second pass over the 2.7 MB frame** (four adds per block).
The reference level, 130, is the measured level of this station as it stands
(2026-10-25 frames: green 130.0 and 134.9, matching `MB_AEC_MEAN` 533 ‰ on the belt), so
**at today's lighting the margin is exactly the measured 12 and nothing about today's
behaviour changes.**

### 1b. Why a chromaticity gate, and why on the mask and not on the cell

A raw channel difference cannot tell a **saturated green object** from a **neutral
surface with a green reflection**. On the empty belt the rule put 368 eroded cells on
the concrete floor's green stain — see `.tmp/maskview/empty_live_new_ruleA.png`: every
false cell is on the floor behind the belt, and **the belt itself produces none**.

The discriminator is dimensionless, so it does not move with the light:

```
rho = 256 · Σ(G − max(R,B)) / Σ(G + R + B)     over the mask's own cells
```

Measured populations: **empty belt 0.9…1.7 at every belt position; real part frames
14.5…32.8.** One division, over the mask's cells only.

A **per-cell** chromaticity threshold was measured and **rejected**: on the newest
frames the part is genuinely pale (2026-10-25 part box B/G/R 165/169/140, r = +1.9,
**no clipping** — 0.00 % of pixels at 255), so a per-cell gate that kills the reflection
also kills the part (572 cells → 161 at r>5 → 103 at r>10). The aggregate asks "is the
*region* an object?", which is the question that has an answer, and keeps the part (the
same frame reads rho 14.5 and publishes 603).

A mask below `PART_CHROMA_MIN 4` is published as **NO PART** — the counts are zeroed and
the mask buffer is zeroed, so the registration has nothing to lock onto. `MB_PART_CHROMA`
says why, so a `MB_PART_PTS` of 0 on a frame with content is explained rather than
mysterious.

### 1c. What is deliberately NOT changed

* the comparison, the registration, the fine pass, the verdict, the AEC, the display;
* `PART_MIN_PTS 400`, the 3×3 erosion, the cluster rule;
* the **background rule and its path** — no line of it changed.

---

## 2. The registration, and why a periodic belt cannot capture it

The brief is right that a periodic texture is the worst case for a translation search,
and that this project has been fooled by one before. Five things stand between the belt
and the answer, in order of strength:

1. **The mask contains no belt cells.** Measured, not asserted: with the gate, the empty
   belt publishes 0 clustered cells *at every belt position tested* (§3). A search cannot
   lock onto points that are not in the mask.
2. **Only `live ∧ mapped reference` points are scored** (`REG_MASK_DOUBLE`, the default
   for every stage — main.c:6089/6098). The belt is in neither mask, so it is in the
   point set at no translation, rotation or scale.
3. **The one rule that can score a live-mask point where the reference says belt is
   `REG_MASK_UNION`**, and it is used **only** on cold stage 1 and **only** when the
   double rule scores nothing at all. With (1), the window in which it runs contains no
   belt cells to attract it.
4. **A mask below the gate publishes no part at all**, so the comparison refuses
   (`MB_DIFF_OK 5`, "nothing to judge") instead of searching. Refusal, not a guess.
5. **The point floor is relative to `min(live, reference)`** (main.c:6134-6146), so a
   frame that offers too few part points refuses rather than registering on whatever is
   left.

What I cannot do offline is prove (2)/(3) on a real belt move; that is what §6 asks the
bench to confirm, via `MB_PART_USED`, `MB_REG_MODE` and whether the reference still
matches.

---

## 3. Offline verification (all of it reproducible without the board)

### 3a. Empty belt, belt moved — the number the owner asked about

The firmware mirror, on the full-resolution empty-belt frame (`dl/live_new.raw`,
2026-10-25 21:14 — the board has been taken off in that image):

| belt move (px) | median | margin | eroded | clustered | **rho** | **MB_PART_PTS** |
|---|---|---|---|---|---|---|
| (0,0) | −17 | 12 | 368 | 265 | 0 | **0** |
| (4,0) | −17 | 12 | 382 | 320 | 1 | **0** |
| (8,0) | −17 | 12 | 368 | 265 | 0 | **0** |
| (16,0) | −17 | 12 | 368 | 265 | 0 | **0** |
| (32,0) | −17 | 12 | 368 | 265 | 0 | **0** |
| (64,0) | −17 | 12 | 368 | 265 | 0 | **0** |
| (0,8) | −17 | 12 | 368 | 265 | 0 | **0** |
| (0,16) | −17 | 12 | 368 | 265 | 0 | **0** |
| (8,8) | −17 | 12 | 368 | 265 | 0 | **0** |
| **(13,7)** | −17 | 12 | 490 | **400** | 1 | **0** |
| (40,20) | −17 | 12 | 402 | 326 | 1 | **0** |

**Two things to read off this table.** First, the goal is met: `MB_PART_PTS` is 0 at
every belt position, against the morning's 430–598 failure. Second, and this is why the
gate is not optional: at the (13,7) shift the **raw** clustered count is exactly **400**
— the gate threshold — so without the chromaticity gate an empty belt would register as a
part at one belt position in the search space. The count alone would have looked fine.

**A shift is a model of the belt having indexed, not the belt having indexed.** The
genuine number needs the bench (§6).

### 3b. Real part frames — the rule must not lose the board

| frame | what it is | green mean | margin | eroded | rho | **MB_PART_PTS** |
|---|---|---|---|---|---|---|
| `st2_A_live` | PCB, 2026-10-23 20:38 balance | 132.7 | 12 | 2599 | 32 | **2596** |
| `st1_a_s0` | PCB, 20:12 balance | 112.5 | 10 | 3179 | 30 | **3179** |
| `live_cam0` | PCB, **2026-10-25 21:11** (current light) | 130.0 | 11 | 1207 | 14 | **603** |
| `st1_now_s0` | PCB, 20:47 balance — the frame whose colour collapsed | 113.3 | 10 | 330 | 0 | **0** (REFLECTION) |

The last row is the honest limitation: on that frame the whole scene lost its green
(p99 +2, max +14 over a median of −21), **no colour rule can see that board**, and the
station refuses. That is the safe direction, and it is visible in `MB_PART_CHROMA`.

The third row is the one that matters for the bench: on the **current** light the part
publishes 603 — only **1.5×** the 400 floor, where the 2026-10-23 frames gave 6.5× and
8×. That thin margin is the main risk this build carries and is why the bench protocol
records `MB_PART_PTS` on every judgement.

### 3c. Light invariance, known answer: the scene did not change

Synthetic uniform gain on a real part frame. Every count that moves is the rule's own
brightness sensitivity.

| frame | case | new rule | vs base | old rule (fixed 12, no gate) |
|---|---|---|---|---|
| `st2_A_live` | ×0.80 | 2571 | **−1.0 %** | −11.4 % |
| `st2_A_live` | ×1.20 | 2614 | **+0.7 %** | +7.7 % |
| `st1_a_s0` | ×0.80 | 3112 | **−2.1 %** | −13.7 % |
| `st1_a_s0` | ×1.20 | 3061 | **−3.7 %** | +3.8 % |
| `live_cam0` | ×0.80 | 613 | **+1.7 %** | −45.4 % |
| `live_cam0` | ×1.10 | 588 | **−2.5 %** | +31.5 % |
| `live_cam0` | ×1.20 | 391 | **−35.2 %** | −49.8 % |

The last row is the prediction that failed (H1). At +20 % on the palest frame the mask
drops below the floor. Stated as a limitation: **this build tolerates roughly ±10 % of
exposure change on the current lighting and not more, on the palest frame.**

### 3d. The mirror is checked against a published number before it reports

`dl/fw_mirror_20261029.py` recomputes, in the firmware's integer arithmetic, the eroded
counts at margin 12 on the two 2026-10-23 frames and **requires 2950 and 2599**, the
numbers `ps_ui/st4_awb_mask.py` published from an independently written implementation.
Both match. Without that check, every table above could be about a different program.

---

## 4. Build facts

| | before | after |
|---|---|---|
| build id | `TSC1327CD597` | **`TSC16F8A77C1`** |
| .text | 120,048 | 120,824 (**+776**) |
| .data | 112 | 112 |
| .bss | 12,092 | 12,108 (**+16** = the four new statics) |
| loadable end | 0x1D560 | 0x1D868 (headroom 10,136 B in `ocm` to 0x20000) |
| .bss in `ocm_free` | 12,092 / 45,056 | 12,108 / 45,056 (headroom 32,948 B) |
| `.bin` | 120,160 B | 120,936 B |
| mailbox words | 421 | 423, **0 collisions** |
| compiler warnings | **4** | **4 — the same four, no new ones** |
| `check_layout.py` | pass | **pass** (384,000 px tiled, all stores aligned) |
| page table overlap | none | none |

The four warnings are pre-existing and unchanged: `dcache_invalidate` implicit
declaration (main.c:934) and conflicting types (1240), `always_inline` (12595),
`wait_probe_edge` unused (1035).

The build is reproducible: `ps_ui.elf`/`.bin`/`.map` were deleted and rebuilt from
scratch for the numbers above.

---

## 5. The word, and the two namespaces it had to miss

**`MB_PART_RULESEL` = word 583**, host-written, firmware-read:
`0` = the background-free colour rule; `1` = the background-difference rule with its
colour fallback, **i.e. exactly the behaviour before this change**; **any other value
means 1.** That last clause is the cold-boot rule: the word is host-written, nothing
initialises it, and DDR holds junk after power-up — the casebook entry where an
uninitialised host word was read as an exposure is why every host-tunable word in this
file is range-checked. A flashed build therefore changes **nothing** until a host writes
the word, which is what a station mid-sweep needs.

**`MB_PART_CHROMA` = word 584**, firmware-written: the live mask's chromaticity,
`0xFFFFFFFF` = not measured.

The range was not taken on trust. `dl/mb_free.py` (the firmware's `#define`s plus its
block writes and literal offsets) and the host map in `dl/host_qc/qc_mailbox.py` **do not
agree on the same free set**, and that difference is exactly where a word would have
collided: 572/573/574 are free in the firmware but owned by the host (`eg_margin`,
`eg_roi`, `ref_avg`), whose highest claim is 582. Checked across both
(`dl/_wordscan_20261029.py`): **583..639 is the only free run, 583 and 584 free, 585.
Word 640 is a magic value, not an index.**

Note also that the brief's "`MB_PART_RULE` word 36" does not match the source: **word 35
is `MB_PART_RULE`** ("which rule built THIS live mask"); **word 36 is `MB_PART_RRULE`**
("which rule built the BASELINE mask"). Both are firmware-written and both still mean
what they meant. The new word records the *selection*, which neither of them did.

### Host side

`qc_mailbox.py` has the two `WordDef`s (so `READ_WORDS` carries them automatically), and
`qc_belt.py`'s cycle CSV gained a **`rule`** column, filled as
`sel=…/act=…/rho=…` on every row — so a row can be attributed without a lookup against
the build. The sequencer's own offline checks are **unchanged**: `--selftest` 38/38 and
`--simulate` 35 checks ok, **identical counts before and after** this change (verified by
running the committed version side by side). The brief's "72/72" does not match either
mode's printed count on this tree, so the comparison made was before/after rather than
against a number in a note.

---

## 6. EXACTLY what the bench will measure — and nothing here claims it

Not measured, and not claimed: **that the same board reads the same DAREA before and
after the belt has indexed.** Nothing below has been run.

**Preconditions (stop and report, do not work around):** one xsdb client at a time; the
A9 debug path is cacheable, so every number comes from the mailbox/AXI-Lite, never a raw
DDR buffer; the belt must be **still** at each judgement, which `qc_belt.py` already
proves with bbox + AEC + the cadence witness.

**Step 0 — identify which motor firmware answers** before any belt command
(`dl/stm32_conveyor_main.c` is framed and the two protocols differ). `qc_belt.py
--identify` sends STOP first, which is safe under both. If the belt cannot be driven:
**move it by hand**, and label every number hand-moved. A hand-moved belt is a valid test
of the mask's independence; it is not a test of the sequencer's timing.

**The measurement — 10 boards, each judged twice** (belt where it is, then after one
index step, belt still):

| per board, per position | word | why |
|---|---|---|
| `MB_DIFF_DAREA` | 23 | **the number that decides it** — same board, same DAREA |
| `MB_DIFF_VERDICT` | 222 | PASS/NG/CANNOT JUDGE must not change |
| `MB_DIFF_OK` | 180 | a refusal is a result, not an error |
| `MB_PART_PTS` | 366 | and `MB_PART_RAW` (21), `MB_PART_EDGE` (167), `MB_PART_INVIEW` (69), bbox 115/116/136/166 |
| `MB_PART_CHROMA` | 584 | the gate's own number; <4 explains a 0 |
| `MB_PART_RULESEL` / `MB_PART_RULE` / `MB_PART_RRULE` | 583 / 35 / 36 | which rule was asked for, which produced the mask, which built the reference |
| registration | `MB_REG_STATE` 232, `MB_PART_USED` 368, `MB_PART_REF` 367, `MB_REG_MODE` 393, `MB_DIFF_SAD` 203 | **a registration failure is a result** — if the reference stops matching after the belt moves, that is the finding |

**And the empty-belt false-part rate on the new rule, before and after a belt move**
(`MB_PART_PTS`, `MB_PART_CHROMA`, `MB_PART_INVIEW`; pass = near zero, and **0 verdicts
of PASS**). This is the direct repeat of this morning's 430–598 test and is the one row
that must be flat.

**Pass / fail, written before the data:** the mask rule is acceptable if, for all 10
boards, `MB_DIFF_DAREA` after the belt move is within the same verdict band as before it
and `MB_DIFF_VERDICT` does not change in the PASS→NG direction, **and** the empty belt
publishes near-zero `MB_PART_PTS` at both belt positions. Anything less, or a DAREA that
moves with the belt, is a fail — including a fail that "looks like" registration.

**How to tell the measurement itself is sound:** `MB_PART_PTS` on a real board must be
in the hundreds (the reference already reads ~500); if it reads 0 the gate is refusing a
real board and the run is testing the gate, not the belt. And the build id must read
`TSC16F8A77C1` before any of it — **read from the board's `MB_FWID` words, not from
`ps_ui/build_id.h`** (see §8).

### The harness

`dl/host_qc/belt_vs_still.py` runs this protocol and writes the CSV.

```
python dl/host_qc/belt_vs_still.py --plan                 # prints the plan, reads nothing
python dl/host_qc/belt_vs_still.py --go --boards 10 --presence-min 400 \
        --log dl/host_qc/logs/bvs_20261029
python dl/host_qc/belt_vs_still.py --go --empty-belt --presence-min 400 \
        --log dl/host_qc/logs/bvs_empty_20261029
python dl/host_qc/belt_vs_still.py --selftest             # the criteria, on scripted rows
```

* **It never writes a mailbox word and never commands the motor.** The operator moves the
  belt and presses Enter; the tool does not send a run command it cannot verify stopped.
* **The stillness proof is not re-implemented**: `StillnessWindow` and `CadenceWitness`
  are imported from `qc_belt.py`, so "still" means exactly what it means to the sequencer
  that shipped — unchanged bbox and area over N reads **and** `MB_PART_TK_N` advancing.
  An unproven window is recorded as `UNPROVEN`, never as still.
* **A refusal is a row, not an error.** `MB_DIFF_OK != 1` is recorded with its code; the
  tool does not retry a registration failure away.
* `--presence-min` has no default on purpose: a guessed threshold would make the run
  measure the guess.
* **The criteria bind — tested.** `--selftest` runs four scripted scenarios, two of which
  *must* fail: a DAREA that crosses the limit with the verdict flipping, and **an empty
  belt at 430 cells** (the morning's own number) which is rejected twice over. A checker
  that has never been shown to reject anything is not a checker.
* Host-side verification after these changes: `check_words.py` — *every defined word
  matches the host map*; `check_readorder_20261029.py` — read order keeps its old prefix,
  the new words are appended; `qc_belt --selftest` 38/38 and `--simulate` 35 checks,
  identical to the committed version.

---

## 8. The incident, and the rule it leaves behind

While building this offline I ran `ps_ui/build.ps1`, which regenerates
`ps_ui/build_id.h`. That file describes the **source tree**; the operator's acquisition
tool uses it to gate evidence against the **running** firmware, and the board was running
the previous build. The gate refused to record frames for a sweep in progress. Nothing was
lost — the sweep was re-run — but the rule is worth writing down:

> **A build stamp read from a file is a claim about the sources. The authority for what
> is running is the running firmware's own words.** `belt_vs_still.py` reads
> `MB_FWID0/1/2` off the board (through the existing `qc_mailbox.decode_fw_id`), never the
> header, and records it on every row; a run whose rows disagree about it is void.

The stop rule that follows: **no build, and no write under `ps_ui/`, while the station is
in use.** The source change for this work is left uncommitted and unbuilt until the owner
sequences it after the sweep.


---

## 7. What I could not settle without the bench

1. **The deciding number**: same board, same DAREA across a real belt index. Everything
   in §3 is a *shift of a still frame* — a model, not the measurement.
2. **That a real belt move does not move the mask.** All the belt positions tested are
   crops of one still frame; they do not have the real belt's motion blur, its seams, or
   a live AEC reacting to it.
3. **The H3 control is missing.** I could not reproduce the documented 646→5825 growth
   offline, because there is no stored background taken at a *different* belt position.
   So this document does **not** demonstrate the old rule failing; it demonstrates the
   new rule holding. The old rule's failure is the project's earlier measurement, cited,
   not re-measured here.
4. **The thin margin on the current light**: `live_cam0` publishes 603 against a 400
   floor (1.5×). Whether that is comfortable on 10 real boards under the station's own
   AEC is a bench question, and it is the main reason the protocol records `MB_PART_PTS`
   at every judgement rather than only the DAREA.
5. **Whether the reference must be re-taken after switching word 583.** The masks are
   produced by different rules, so a reference built under one and a live frame under the
   other are not the same quantity; `MB_PART_RRULE` (36) exposes the mismatch. The
   correct procedure is being established at the bench, not asserted here.
