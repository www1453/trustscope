#!/usr/bin/env python3
"""null_floor.py -- measure a statistic's floor BEFORE spending a population on it.

WHY THIS EXISTS (the afternoon it cost)
    Two new statistics were implemented, then a 54-placement acceptance plan was built to
    set their thresholds from a good-board population.  At the FIRST placement -- the
    reference board judged against itself, where the correct registration is the identity
    and no defect can be blamed -- the readings were 141..150 outline cells and 44..80
    within-cell-range cells.  The corner chip and the scratch those statistics exist to
    catch read 3..4 and 11.  The plan was measuring a population whose floor was already
    above its signal: fifty boards would not have told us anything the first one did not.

    A null is cheap.  A population is not.  So the null comes first, and it is a computation.

WHAT IT COMPUTES
    max(null)                    the floor: what the statistic reads when nothing is wrong
    min(defect)                  the signal: the smallest reading a real defect produced
    separation = min(defect) - max(null)
    PASS when separation > margin (default 0), FAIL otherwise.

    A FAIL is not "tune the threshold harder".  It means the statistic's null overlaps the
    readings it must separate, so no threshold can separate them, so change the STATISTIC
    (and then measure ITS null, which is the step everyone skips).

    You may also give the defect reading directly with --known-defect-max when no defective
    sample exists yet: a null above a physically known defect size kills the statistic just
    as dead, and is one board cheaper to obtain.

USAGE
    python null_floor.py rows.csv --value out_area --class board \\
        --null-label selfnull --defect-label chip
    python null_floor.py rows.csv --value eg_cells --class kind \\
        --null-label same --known-defect-max 11
    python null_floor.py --selftest

    The csv needs a value column and a class column; everything else is ignored.  Rows whose
    class is neither null nor defect are reported as "other" and excluded from the verdict.

EXIT CODES
    0 PASS | 1 FAIL (the statistic cannot carry the decision) | 2 usage/parse error

LIMITS, stated because they decide whether this tool lies to you
    * The null must be a TRUE null -- the same object, the same placement, the correct
      answer known by construction.  Two different boards of the same model is NOT a null.
    * --known-defect-max is whatever your specification says the defect measures; if that
      number is itself a guess, the verdict inherits the guess.
    * It reads one statistic at a time on purpose.  A statistic that passes here can still
      fail on a population (thresholds, spread, false-NG rate) -- this checks the floor,
      which is the failure that wastes the population.

ASCII ONLY.  Pass the csv; no project paths are baked in.
"""
import csv
import io
import sys


def pct(vals, q):
    if not vals:
        return None
    s = sorted(vals)
    if len(s) == 1:
        return s[0]
    pos = (len(s) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def parse_labels(s):
    return [x.strip() for x in s.split(",") if x.strip()]


def load(path, value_col, class_col):
    rows = []
    with io.open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        rdr = csv.DictReader(f)
        if rdr.fieldnames is None:
            raise ValueError("empty csv")
        for name in (value_col, class_col):
            if name not in rdr.fieldnames:
                raise ValueError("column %r not in %s (has: %s)"
                                 % (name, path, ", ".join(rdr.fieldnames[:12])))
        for row in rdr:
            raw = (row.get(value_col) or "").strip()
            if not raw:
                continue
            try:
                v = float(raw)
            except ValueError:
                continue
            rows.append((v, (row.get(class_col) or "").strip()))
    return rows


def describe(name, vals):
    if not vals:
        print("  %-22s n=0" % name)
        return
    print("  %-22s n=%-4d min=%-10.4g p50=%-10.4g max=%-10.4g"
          % (name, len(vals), min(vals), pct(vals, 0.5), max(vals)))


def evaluate(rows, null_labels, defect_labels, known_defect_max=None, margin=0.0):
    """Return (verdict, detail dict).  verdict in {"PASS","FAIL","UNDECIDED"}."""
    nulls = [v for v, c in rows if c in null_labels]
    defects = [v for v, c in rows if c in defect_labels]
    other = [v for v, c in rows if c not in null_labels and c not in defect_labels]
    print("  groups")
    describe("null", nulls)
    describe("defect", defects)
    if other:
        describe("other (excluded)", other)
    d = {"n_null": len(nulls), "n_defect": len(defects)}
    if not nulls:
        print("  UNDECIDED: no null rows.  The floor is the whole point -- measure it.")
        return "UNDECIDED", d
    floor = max(nulls)
    d["floor"] = floor
    if defects:
        signal = min(defects)
        d["signal"] = signal
        d["source"] = "measured defective sample"
    elif known_defect_max is not None:
        signal = float(known_defect_max)
        d["signal"] = signal
        d["source"] = "--known-defect-max (specification, not a measurement)"
    else:
        print("  floor: max(null) = %g" % floor)
        print("  UNDECIDED: no defect arm.  A null alone cannot ACCEPT a statistic, but it")
        print("  can KILL one: pass --known-defect-max <reading> if the defect size is known.")
        return "UNDECIDED", d
    sep = signal - floor
    d["separation"] = sep
    print("  floor  max(null)      = %g" % floor)
    print("  signal min(defect)    = %g   (%s)" % (signal, d["source"]))
    print("  separation            = %g   (need > %g)" % (sep, margin))
    if sep > margin:
        print("  VERDICT: PASS -- the null floor is below the smallest signal on this bench.")
        return "PASS", d
    print("  VERDICT: FAIL -- the statistic cannot carry this decision on this bench.")
    print("  Its null floor is at or above the reading it must separate, so NO threshold")
    print("  separates them.  Do not run the population: change the statistic, then")
    print("  measure ITS null before anything else.")
    return "FAIL", d


SELFTEST_ROWS = {
    "separable.csv": (
        "kind,out_area\n"
        "selfnull,3\nselfnull,5\nselfnull,7\n"
        "chip,20\nchip,26\nchip,41\n"),
    "floor_above_signal.csv": (
        "kind,out_area\n"
        "selfnull,141\nselfnull,150\nselfnull,149\n"
        "chip,3\nchip,4\nchip,7\n"),
}


def selftest():
    import os
    import tempfile
    tmp = tempfile.mkdtemp(prefix="null_floor_selftest_")
    bad = 0
    cases = [("separable.csv", "PASS"),
             ("floor_above_signal.csv", "FAIL")]
    for name, want in cases:
        p = os.path.join(tmp, name)
        with io.open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(SELFTEST_ROWS[name])
        print("  selftest %s" % name)
        rows = load(p, "out_area", "kind")
        verdict, _d = evaluate(rows, ["selfnull"], ["chip"])
        ok = verdict == want
        bad += 0 if ok else 1
        print("  selftest %-24s want %s, got %s  %s"
              % (name, want, verdict, "PASS" if ok else "FAIL"))
    print("  selftest: %d/%d cases passed" % (len(cases) - bad, len(cases)))
    return 0 if bad == 0 else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    path = None
    opt = {"--value": None, "--class": None, "--null-label": None,
           "--defect-label": None, "--known-defect-max": None, "--margin": "0"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in opt:
            i += 1
            if i >= len(argv):
                print("%s needs a value" % a, file=sys.stderr)
                return 2
            opt[a] = argv[i]
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif a.startswith("-"):
            print("unknown option %s (see --help)" % a, file=sys.stderr)
            return 2
        else:
            path = a
        i += 1
    if not path or not opt["--value"] or not opt["--class"] or not opt["--null-label"]:
        print("need: CSV --value COL --class COL --null-label NAME[,NAME]", file=sys.stderr)
        print("see --help", file=sys.stderr)
        return 2
    try:
        rows = load(path, opt["--value"], opt["--class"])
    except Exception as exc:
        print("cannot read %s: %s" % (path, exc), file=sys.stderr)
        return 2
    if not rows:
        print("no numeric rows in %s under column %r" % (path, opt["--value"]),
              file=sys.stderr)
        return 2
    known = float(opt["--known-defect-max"]) if opt["--known-defect-max"] else None
    margin = float(opt["--margin"] or 0)
    print("statistic %r from %s (%d rows)" % (opt["--value"], path, len(rows)))
    verdict, _d = evaluate(rows, parse_labels(opt["--null-label"]),
                           parse_labels(opt["--defect-label"] or ""), known, margin)
    return {"PASS": 0, "FAIL": 1, "UNDECIDED": 2}[verdict]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
