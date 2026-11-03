# The last build of the deadline: camera 1's registration names its own refusal

> Build `TSC14A817456` (ELF 206,504 B, bin 127,444 B, loadable image ends 0x1F1D4).
> Loaded with `ps_fft_dual/strict_load_cores.tcl`.  One build, one bench pass.
> This note is the record of what the build changes and what it deliberately does not.

---

## 1. What was wrong, in the words of the running station

On the previous build (`TSC1EF097D3C`), with a clean good board in view and both
references taken, the mailbox read:

| word | camera 0 | camera 1 |
|---|---|---|
| `diffok` | 1 (compared) | **5 (REFUSED_REGISTRATION)** |
| `fvalid` | 539 | **0** |
| `fcells` | 0 | **0xFFFFFFFF** |
| part mask `pts` | 628..683 | 382..392 |
| baseline `ref` | 575 | **330** |
| `regstate` | 1 | **2** |
| `regerr` | 18..20 | **0xFFFFFFFF** |

`and_ok = 0`, `and_why = 2` (camera 1 refused), so the 26-board dump never ran.

The registrar refused **before its first stage**.  `reg_search()` gates on

```c
if (g_part_pts < PART_MIN_PTS || g_part_ref < PART_MIN_PTS) { refuse; }
```

with `PART_MIN_PTS = 400`, a constant calibrated on **camera 0**, whose reference mask is
575.  Camera 1's reference mask is 330 and a clean good board reads 288..405: the floor
demanded **more part points than a good board produces in camera 1's framing**.  The
reference itself failed the gate, so `regerr` stayed at the sentinel the refusal passes
(`0xFFFFFFFF`) and `fcells` stayed at the other one.  The ROI was never involved, and the
ROI sweep in the task description already proved that.

## 2. What fed the seed before, and what feeds it now

**Before (and this is the exact answer, not a reconstruction).**  Camera 1's registration
was seeded by `reg_restore_hold()` from camera 1's own per-view held transform:
`ref_take()` for view 1 installs the identity prior (dx 0, dy 0, scale 1.0, angle 0)
because the reference is copied from a live frame, and every later comparison starts from
the last transform camera 1's own search adopted.  The cold search that follows is over
camera 1's live lattice against camera 1's own `BASE_GM` / `BASE_MASK` (its own reference).

There was **no cross-view term in the code path** -- `MB_AND_OX/OY` is written by
`dual_and_build()` *after* both views have been compared and is never read by
`reg_search()`.  What was wrong was not the seed but the **gate in front of it**: the
search was not allowed to start, so the seed was never exercised and nothing about it was
published.  The one number that could have said so (`regerr`) is a sentinel, which is why
today's diagnosis was ambiguous.

**Now.**  The seed is the same camera 1's own held transform, recorded **before any stage
can refuse** and published as four words:

| word | meaning |
|---|---|
| `cam1_seed` | `(dy&lt;&lt;16)&#124;dx` in 1/16 SOURCE px -- the same unit as `MB_DIFF_DX/DY` |
| `cam1_seedsc` | `(angle100&lt;&lt;16)&#124;scale256`, angle in 1/100 degree, scale in 1/256 |
| `cam1_conv` | the transform the search **converged** on, same packing |
| `cam1_convsc` | its scale and angle |

Equal seed and converged means the search never moved -- either it was never allowed to
run (`cam1_regwhy` says which) or nothing beat the prior.  The floor in front of the
search is now the **view's own**: camera 0 keeps `PART_MIN_PTS = 400` bit for bit;
camera 1 uses **half of its own reference mask, clamped to 128..400** (165 at today's
330).  Half is the same "the overlap can only reach the smaller mask" rule
`reg_score()` already applies to its own point floor; 128 is far above the empty belt
(0 on ten reads) and below every good-board reading.  A reference below 256 points gives a
floor of 128, and a frame whose mask is under that is still refused, so an empty belt
still refuses.

**This is the fifth thing, and it is disclosed rather than hidden.**  The four required
items are implemented as four items; this floor change is what makes the first of them
("camera 1's registration is a search of camera 1's frame against camera 1's own
reference") true at all, because a gate that refuses every camera-1 reference means the
search is never a search.  It changes no verdict rule, no tolerance, no limit and no
camera-0 number.

## 3. The sentinel rule (item 2)

`0xFFFFFFFF` now means exactly one thing: **the pass never ran**.

| state | `fvalid` | `fcells` |
|---|---|---|
| the fine pass never ran (registration / light / clip refusal, settle slot's predecessor) | 0 | 0xFFFFFFFF |
| the fine pass **ran and judged no cell** | 0 | **0** |
| the fine pass judged and persisted cells | > 0 | n |
| the pass ran, judgement withheld (persistence window) | > 0 | 0xFFFFFFFF, and `cam1_regwhy = 6` says so |

The branch that published `fcells = 0xFFFFFFFF` for a completed pass that judged nothing
is gone.  A settle slot is now distinguishable from "never ran" by its `fvalid > 0` and by
the sub-code, instead of by guessing.

## 4. The sub-code (item 3)

`MB_CAM1_REGWHY` (word 635) is published on **every** camera-1 comparison, refusals
included:

| value | meaning |
|---|---|
| 0 | no refusal: the search published a usable transform |
| 1 | part not wholly in view (the live mask reaches the frame's border ring; `diffok = 6`) |
| 2 | search did not converge (nothing scoreable / window edge / error above the limit) |
| 3 | too few valid cells (the live or baseline mask is below THIS view's floor) |
| 4 | reference/tolerance not ready (no usable reference, or empty structure lattices) |
| 5 | unclassified -- fail-safe, so a new refusal can never publish 0 |
| 6 | the transform was adopted but is too young to judge (persistence window) |

`diffok = 5` with `regwhy = 0` is therefore not possible: a `5` always carries a named
reason.  Note that the per-cell tolerance map being unlearned (`tol_n = 0`, so cells are
judged against the fixed 30-grey floor) is **not** a refusal and does not publish 4; 4 is
reserved for a missing reference/lattice, which is the only "not ready" state that stops
the search.

## 5. The four diagnostic words (item 4)

| word | what it answers |
|---|---|
| `cam1_bb0` / `cam1_bb1` | the live mask's bbox in lattice cells, `(by&lt;&lt;16)&#124;bx`, 0xFFFFFFFF in a half = no cell on that side |
| `cam1_medge` | mask cells that reach the ROI band's edge (counted over the three outermost rows each side, because the band is applied before the 3x3 erosion and the literal edge row can never hold a mask cell).  `> 0` = the mask is truncated by the ROI. |
| `cam1_seed` / `cam1_seedsc`, `cam1_conv` / `cam1_convsc` | where the search started and where it ended |
| `cam1_ncc` | the normalised cross-correlation of the gain-compensated gradient magnitudes at the converged transform, per 1000.  Unlike the match error it is scale-free, so 1000 means "the same structure", not "small numbers".  0xFFFFFFFF = not measured (< 32 points). |

Nothing in this block is read by `diff_verdict()`, by the AND, by the mask rule or by the
search itself.  They are writes only.

## 6. What was deliberately not done

* **No homography/affine in the firmware.**  The cross-view correspondence belongs to the
  offline analysis; a fixed matrix baked into an image that cannot be rebuilt after the
  deadline is the wrong trade.
* **No use of `MB_AND_OX/OY` as a seed or a gate.**  The offset's sign is known wrong and
  using it would make camera 1's registration depend on a quantity the offline work owns.
* **No change to the AND's mapping or its verdict rule**, no change to camera 0's floor,
  no change to `PART_MIN_PTS` itself.
* **No tuning after the gate is read.**  If the gate says 5, the station stops and reports
  the sub-code and the four words; a refusal with a named reason is a result.

## 7. Bench record

Filled from the station, in order.  (See the commit that carries this file for the final
numbers.)

```
build        TSC14A817456   ELF 206,504 B   bin 127,444 B   end 0x1F1D4
loader       ps_fft_dual/strict_load_cores.tcl (rst -cores, dow, con)
after load   frames advanced 126 -> 160, v0_frame 3 -> 5, v1_frame 3 -> 5
             aec_state 1, aec_exp 8662, exp_lock 8662 (already at equilibrium)
             cam1 before the background/reference: regwhy 3, mask empty
```
