# Independent annotation of the seven scratch boards (2026-10-28)

**What this file is.** The first label in this project that does not come
from the comparison. Seven boards (`d6 d7 d8 d9 d10 d11 d12`) were shown to
the operator as seven numbered sheets, each with three candidate rectangles
(A/B/C) at 6x plus the whole part with the three marked. The operator picked
the rectangle containing the scratch, or said none / could not tell. The
candidate rectangles came from the per-cell |d| of that board against the
reference (the rule's own per-cell measurement, used only as a place to
*look*), weighted away from the metallic coil; a colour-only pale-scuff
detector was the fallback. No rule verdict was shown.

- confirmed via: session Q&A relayed through the parent session; seven numbered candidate sheets dl/ann_retrain/view/ask_<board>.png
- confirmed at: 2026-10-28T16:38:20+08:00
- who: the project operator (the person who labelled the boards during the sweep)
- provenance: the operator's answers are a session record (relayed through
  the parent session); every other number in this file comes from a file, a
  CSV column or a command.
- record: `dl/annotation_20261028.json`, SHA256 `dbc3eddb9f006edc12708a441194d0b48074dbd5abb776a77f9124cb0d586748`

| board | class | answer | rectangle (x0,y0,x1,y1) | source |
|---|---|---|---|---|
| d10 | scratch | C | [308, 396, 404, 492] | fine_deep>tol group, mask-weighted |
| d11 | scratch | C | [452, 348, 548, 444] | fine_deep>tol group, mask-weighted |
| d12 | scratch | NONE | - | - |
| d6 | scratch | A | [358, 500, 454, 596] | fine_deep>tol group, mask-weighted |
| d7 | scratch | NONE | - | - |
| d8 | scratch | NONE | - | - |
| d9 | scratch | A | [316, 388, 412, 484] | fine_deep>tol group, mask-weighted |

**Confirmed: 4 of 7. Empty: d7, d8, d12** -- the operator looked at the
three magnified candidates on each and none was the scratch. The empty
label is a recorded answer (`"label": null`, `"reason": "operator: none of
the three candidates"`), not a gap and not something to be inferred later.

**What the label can and cannot buy (computed from the sweep CSV).**

- confirmed and the rule already detects them: d10, d6 -- improving on these cannot change the detection count.
- confirmed and the rule misses them: d11, d9 -- these are the only boards the annotation can add to detection.
- rule misses with **no** label: d12 -- the third improvable board is lost for this round and is not guessed.
- so the labelled headroom is **2 boards** (d9, d11) out of the 19 the rule judged; a perfect result on them cannot move detection by more than 2.

**Limit of the label, and a fact about the dataset.** The operator could not
identify the defect on 3 of the 7 scratch boards even with three magnified
candidates. This is not an operator failure: it means the independent-pixel-
label that this class would need does not exist in practice at this scale.
A rectangle is not a pixel-accurate scratch mask either: it says where the
operator saw the scratch, but the path of the 2-3 px line inside the 96x96
rectangle is not recorded, so **how many of the 9 windows per board actually
cross the line cannot be counted**. All 9 are inside the rectangle; that is
the strongest true statement. The label is independent, not pixel-exact, and
it is reported that way.
