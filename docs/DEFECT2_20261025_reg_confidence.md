# Defect 2 (2026-10-25) — the registration escalates on low confidence, not only on refusal

Build **`DE833091`** (source hash), flashed with `ps_fft_dual/strict_load_cores.tcl` only:
no bitstream, no power cycle, no VDMA poke.  It is Defect 1's `EBF0919B` plus this change.
Reported numbers are on the board, on the scene that was on the belt at the time.

**Headline, stated first because it is a partial result: the wrong answers' gross failures
are gone and the worst pair improved 2.5x, but the acceptance target (1 px / 0.3 deg on
every known-truth pair) was NOT reached.  Section 4 says where the remaining error is, and
it is measured, not argued: with the Defect-1 mask the firmware's own error function has its
minimum about 4 source pixels from the truth on this scene, so no escalation policy that
minimises that function can reach 1 px.**

---

## 1. The regression, reproduced on the board before the fix

Stage E measured it (`dl/STAGE_E_20261025_not_background_mask.md` section 3.4): on three
pairs whose truth an independent fit recovers exactly, the firmware published a local answer
2.6..30.5 source px and up to 7.77 degrees off, residual 10x the truth's.  Mechanism: the
widened (DIL1/union) cold search is entered only when the shipped search **refuses**
(`e_inc == 0xFFFFFFFF`); stage E's larger mask made the held answer always score, so the
search never refused and never widened.

**Reproduced again today** (build `EBF0919B`, the real defective board on the belt, three
known-truth pairs built from the current placement with `stE_part_shift.py` /
`stE_shift_ref.py`, then injected with `MB_CMD = 17`; truth from `ps_ui/stD_reg_fit.py`):

| pair | truth (independent fit) | old build published | error | fit's residual: published / at truth |
|---|---|---|---|---|
| part +30.5/−9.25 px, −0.20 deg | dx16 −488, dy16 +144, −20, 256 | −572, +162, −63, 253 | 5.25 px / 1.1 px / 0.43 deg | 25.43 / **3.61 grey** |
| part +56.5/−18.25 px, −0.40 deg | dx16 −904, dy16 +296, −40, 256 | −924, +360, +8, 259 | 1.25 px / 4.0 px / 0.48 deg | 16.89 / **3.70 grey** |
| whole scene +56.5/−18.25, −0.40 deg | dx16 −904, dy16 +296, −40, 256 | −874, −284, +512, 240 | 1.88 px / **36.25 px** / **5.52 deg** | 39.09 / **3.62 grey** |

Every row was published by `MB_REG_MODE` 2 (HOLD, a candidate lost to the held answer) or 5
(RE-AIM) with `MB_REG_RULE` **0** — the shipped double rule, i.e. the widened search was
never entered.  The instruments are `dl/`… no: `ps_ui/stD_reg_fit.py` (the independent fit),
`ps_fft_dual/stF_pair_20261025.tcl` (inject + dump) and `ps_ui/stF_reg_score.py` (below).

---

## 2. What decided the bound: the firmware's own error function, replayed and checked

`REG_ERR_LIM` (480 = 30 grey) answers "is this frame this part at all"; it cannot answer
"is this ALIGNMENT right".  The number that can is `reg_score()` — the same arithmetic the
search minimises, published as `MB_REG_INCERR`.  It is a pure function of five stored
buffers, so it was replayed in Python (`ps_ui/stF_reg_score.py`).

**The replay is checked against the board, not assumed:** for the transform the board held
at 11:26 (dx16 −544, dy16 −104, angle100 737, scale256 257) it returns **405** where the
board published `MB_REG_INCERR` **403**, over 578 of the board's 577 scored points.  Two
further known-answer checks: a reference against itself at the identity is the minimum of
its own surface, and a reference shifted by exactly one lattice cell has its minimum at
exactly that shift.

Populations, in 1/16 grey, with the Defect-1 mask (`BG_MASK_THR` 24, background rule):

| population | measured |
|---|---|
| CORRECT answers (three pair truths + the still scene at the identity) | **96, 149, 152, 129** = 6.0 .. 9.5 grey |
| WRONG answers the old build published on the same pairs | **225, 303, 309** = 14.1 .. 19.3 grey |

`REG_CONF_LIM = 192` (12.0 grey) is the largest round value inside that measured gap:
1.26x above the worst correct answer, 1.17x below the best wrong one.

**What the fix does with it** (`ps_ui/main.c`):

1. **`4934`** — `can_widen` is set not only when the held answer is unscoreable but also
   when its score is above `REG_CONF_LIM`: a scoreable answer that is not a believable one
   may widen too.  This is the escalation the brief asks for.
2. **`4947`, `4955`** — the warm/hold shortcut now requires a CONFIDENT held answer
   (`e_inc <= REG_CONF_LIM`).  Above it the code falls through to the full cold search
   instead of re-publishing.  A warm candidate must also be confident in its own right.
3. **`5324`** — a cold answer above `REG_CONF_LIM` goes through `REG_COLD_FAIL`: on the
   shipped rules that escalates to the widened rules, on the widened rules it is refused.
   This is what makes "the wrong answers stop being published" true rather than hoped for.
4. **`5349`, `5355`** — in the cold path's stage-0 gate, "better" and "the held answer still
   fits" now use `REG_CONF_LIM` instead of `REG_ERR_LIM` / the old 15-grey `REG_HOLD_LIM`
   (which is superseded and removed).  A low-confidence held answer can no longer be
   re-published, and if the cold answer does not beat it the frame goes UNSTABLE
   (state 3 → CANNOT JUDGE) instead of publishing either.

`REG_ERR_LIM`, the margins, the warm window, the re-aim bound, the cold search's geometry,
the mask rules and the comparison are unchanged, so a confident answer takes exactly the
path it took before.

---

## 3. Measured: before vs after, on the same scene, the same pair files

| pair | old build published | new build published | fit residual old → new | error (new) |
|---|---|---|---|---|
| identity (still scene) | −4, 0, +13, 257 | −4, 0, +13, 257 | — | 0.25 px / 0.13 deg |
| part +30.5/−9.25 | −572, +162, −63, 253 | **−518, +128, +40, 255** | 25.43 → **17.06** | 1.88 px / 1.0 px / 0.60 deg |
| part +56.5/−18.25 | −924, +360, +8, 259 | **−968, +320, −9, 255** | 16.89 → **16.78** | 4.0 px / 1.5 px / 0.31 deg |
| whole scene +56.5/−18.25 | −874, −284, +512, 240 | **−966, +318, −5, 255** | 39.09 → **15.39** | 3.88 px / 1.38 px / 0.35 deg |

What improved, plainly: the worst pair's dy error fell **36.25 px → 1.38 px** and its angle
**5.52 deg → 0.35 deg**, its fit residual **39.09 → 15.39 grey** (2.5x); the first pair's
residual fell 25.43 → 17.06; every published answer now sits in the same basin as the truth
instead of a randomly different one, and the still scene still holds the identity to
0.25 px / 0.13 deg.

What did NOT improve: the second pair (16.89 → 16.78 grey, 4.0 px in x), and **no pair
reaches 1 px / 0.3 deg**.  The new answers read `MB_REG_INCERR` 71..109, i.e. all under the
confidence bound — so on this scene the fix does not even fire for them; it fires only on
the gross failures.  That is the honest result and the reason is in the next section.

---

## 4. Why 1 px is not reachable by this change — measured

`reg_score()` samples the live **lattice**: four GREEN pixels per 8x8 cell, on a 4-pixel
grid, compared against one nearest neighbour of the half-res baseline, over the part mask.
That is a coarse, aliased measure, and with the Defect-1 mask it is an average over ~700
cells of which the white silkscreen matches the belt: the wrong answers score *low* on it.
Replaying it over the dumped state of the second pair, its minimum sits at
**(−968, +356)** while the independent fit puts the truth at **(−904, +296)** — **2
half-res pixels = 4 source pixels away**, inside the same basin the search then publishes.

So the remaining error is the objective function's sampling, not the escalation policy: a
search that minimises `reg_score()` cannot publish better than that function's minimum.
That is also why the acceptance's instrument (which samples 16 positions per cell at full
resolution) separates the truth at 3.6 grey from the published answers at 15-17 grey, while
the firmware's own word reads 71-109 (4.4-6.8 grey) for both.

**The next lever, stated but not taken here** (it is a different change, in the measurement
rather than in the control flow): score the search on the fine sampler (`ref_cell8`'s
16 positions per cell, full-resolution green) and/or restrict the scored cells to those
with local contrast, so that the function the search minimises has its minimum at the
alignment the comparison needs.  Until that exists, this build's registration is
"never grossly wrong, sometimes a few pixels off", not "0.13 px".

---

## 5. Cost

| item | Defect 1 (`EBF0919B`) | this build (`DE833091`) |
|---|---|---|
| `.text` | 107,276 | **107,316** |
| `.bss` | 11,516 | 11,516 |
| image end (incl. `.bss`) | 0x1D064 (118,884) | **0x1D08C (118,924)** |
| **OCM free** | 12,188 | **12,148** |

Build: 13 files, 0 mailbox collisions (336 words / 336 indices), all layout checks pass, the
four pre-existing warnings.  No new mailbox words.

---

## 6. The combined acceptance numbers, measured on `DE833091`

| acceptance | measured | how |
|---|---|---|
| empty belt: `MB_BG_CELLS` and the part mask both small | `MB_BG_CELLS` **0** (0..15 over 24 s), `MB_PART_RAW` **0**, `MB_PART_PTS` **0**, `MB_BG_MEDD` 1..2 | `MB_CMD = 12` with the belt empty, 17 comparisons watched (`stF_bg_20261025.tcl`) |
| real part in view: mask comfortably above the floor, background rule, no fallback | `MB_PART_RAW` **764**, `MB_PART_PTS` **764** (1.91x `PART_MIN_PTS` 400), `MB_PART_REF` 746, `MB_PART_RULE` **1**, `MB_PART_RRULE` **1**, `MB_PART_BGWHY` **0** | fresh reference (`MB_CMD = 9`) with the defective board in view |
| still scene, 100+ comparisons, no mask-attributable refusal, no forbidden PASS | **186 judged comparisons in two runs** (96 + 90), **0 refused** (0 mask-attributable, 0 other); all on the background rule; `MB_PART_PTS` 434..940 and 444..816; max raw fine count **4** and **0**; max `MB_DIFF_DAREA` **6** and **0**; PASS with the raw count ≥ 8: **0**; PASS with `DAREA` ≥ 8: **0** | `stE_accept_20261025.tcl still 200 600` and `still 170 600`, one row per judged comparison |
| the four/six slots that were not PASS | `MB_READY` **0** at those instants (`MB_AVG_CNT` had restarted: 1 or 5..7), i.e. the settle gate saw motion and withheld the judgement | the same rows; not attributable to the mask or the registration, and the direction is CANNOT JUDGE, never PASS |
| registration within 1 px / 0.3 deg on the known-truth pairs | **NOT MET**: 1.9-4.0 px and 0.31-0.60 deg; gross failures gone (section 3, 4) | `stD_reg_fit.py` truth vs the published transform |
| a known defect still reads NG through this mask | `MB_CMD = 15`, 40x40 px, +60 grey at cell (119,63) → `MB_DIFF_DAREA` **16**, `DAMP` 59..65, `DBOX` **(119,63)-(123,67)** = exactly the stamped 5x5 cells, verdict **1 (NG)** | `stE_accept_20261025.tcl stamp 119 63 40 60 40` |
| defective board against a GOOD reference reads NG | **NOT MEASURED — needs a good board on the belt.**  The only reference taken today is the defective unit itself, and the same-board comparison correctly reads PASS (`DAREA` 0).  The stamp above is a path check, not a QC result. | — |

---

## 7. What remains unverified, and the human steps

1. **A good board, referenced, then the defective board against it.**  This is the one
   acceptance that cannot be made from what was on the bench: the only reference taken today
   is of the defective unit.  *Human:* place a good PCB in the same framing, `MB_CMD = 9`,
   check `MB_PART_REF` > 400 and `MB_PART_RRULE` = 1; then place the defective board and
   read 20 comparisons of `MB_DIFF_DAREA` / `MB_DIFF_DAMP` / `MB_DIFF_DBOX` /
   `MB_DIFF_VERDICT`.  Expected `DAREA` ≥ 8 and NG.
2. **The registration's accuracy after a *good* reference.**  Every pair here was built from
   the defective board's own frames.  The 4-pixel objective-function bias measured in
   section 4 is a property of the *frame and mask*, not of the board's quality, but it was
   only measured on this one.
3. **The widened search's behaviour on a large real placement.**  It was entered on the third
   pair (its residual more than halved) but the scene's placement was small; the stage-D
   large-placement experiment was not repeated.
4. **`REG_CONF_LIM`'s upper side.**  A good part under a different light could read between
   192 and 480 and be refused when there is no held answer to fall back on.  That direction
   is CANNOT JUDGE, never PASS, and the three correct answers measured have 26% headroom.
5. **The 4-sample lattice itself** (section 4).  The next change is in the objective
   function, not in the escalation, and it is not in this commit.
