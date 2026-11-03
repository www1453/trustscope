#!/usr/bin/env python3
"""casebook_index.py -- is the symptom index still true?  Count it, do not assert it.

WHY THIS EXISTS
    A casebook's index ("find your symptom in the table") is the only part anyone reads, and
    it is hand-written, so it rots: it silently fell behind its own files here (indexing
    36 entries while the files carried 139), and once quoted a wrong count in the text above
    the table.  A hand-written "coverage: 80%" would rot the same way, so nothing here is
    hand-written.

    It also checks for PHANTOM references -- an index row pointing at an ID that no longer
    exists.  That is worse than a missing row: the reader is told the answer exists and finds
    nothing, which costs exactly the time the index was meant to save.

WHAT IT COUNTS
    entry   : a '## ' heading whose first token is an ID -- [A-Z]+<digits> with an optional
              single-letter suffix (M25b is its own entry), or a CJK '<word> N' heading used
              by some casebooks.
    indexed : an ID referenced from the index file as  § ID  /  § **ID**  /  section **ID**
    coverage: indexed / entries, printed, never authored.

USAGE
    python casebook_index.py skill/pitfalls                  # dir + its README.md
    python casebook_index.py skill/pitfalls --index README.md --min-coverage 30
    python casebook_index.py --selftest

    Default index file is any of README.md / INDEX.md / 00-index.md in the directory.

EXIT CODES
    0 clean | 1 phantom reference, or coverage below --min-coverage | 2 usage error

LIMITS
    Textual, so: an entry heading that does not start with an ID is invisible to it, and an
    ID mentioned in prose counts as indexed.  It measures the index's reach, not its quality.
    Both limits are on purpose -- the alternative is a parser for a format nobody fixed.

ASCII ONLY in the source; the CJK heading pattern is written as escapes.
"""
import io
import os
import re
import sys

ENTRY_RE = re.compile(r"^##\s+([A-Z]{1,3}\d+[a-z]?)\b", re.M)
CJK_RE = re.compile(r"^##\s+\u5751\s*(\d+)", re.M)          # 'keng N' -> reported as kengN
REF_RE = re.compile(r"(?:\u00a7|\u8282)\s*\**\s*([A-Z]{1,3}\d+[a-z]?)")
DEFAULT_INDEX_NAMES = ("README.md", "INDEX.md", "00-index.md")


def read(path):
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def find_index(pit_dir, explicit=None):
    if explicit:
        p = explicit if os.path.isabs(explicit) else os.path.join(pit_dir, explicit)
        return p if os.path.exists(p) else None
    for name in DEFAULT_INDEX_NAMES:
        p = os.path.join(pit_dir, name)
        if os.path.exists(p):
            return p
    return None


def scan(pit_dir, index_path=None):
    entries = {}          # id -> filename
    per_file = []
    for fn in sorted(os.listdir(pit_dir)):
        if not fn.lower().endswith(".md"):
            continue
        p = os.path.join(pit_dir, fn)
        if index_path and os.path.abspath(p) == os.path.abspath(index_path):
            continue
        text = read(p)
        ids = ENTRY_RE.findall(text) + ["keng%s" % n for n in CJK_RE.findall(text)]
        per_file.append((fn, ids))
        for i in ids:
            entries[i] = fn
    indexed = set()
    if index_path:
        indexed = set(REF_RE.findall(read(index_path)))
    known = set(entries)
    return {
        "entries": entries,
        "per_file": per_file,
        "indexed": indexed,
        "phantom": sorted(indexed - known),
        "missing": sorted(known - indexed),
        "coverage": 100.0 * len(indexed & known) / max(1, len(known)),
    }


def report(pit_dir, index_path, res, min_coverage=0.0):
    print("dir   : %s" % pit_dir)
    print("index : %s" % (index_path or "(none found -- every entry counts as missing)"))
    print("")
    print("%-34s %s" % ("file", "entries"))
    for fn, ids in res["per_file"]:
        print("%-34s %s" % (fn, "%d" % len(ids) if ids else "(no ID headings)"))
    print("-" * 60)
    print("entries total : %d" % len(res["entries"]))
    print("indexed ids   : %d" % len(res["indexed"] & set(res["entries"])))
    print("coverage      : %.1f%%" % res["coverage"])
    if res["missing"]:
        print("not indexed   : %s" % " ".join(res["missing"]))
    if res["phantom"]:
        print("PHANTOM (the index points at an entry that does not exist): %s"
              % " ".join(res["phantom"]))
    return res["phantom"], res["coverage"]


SELFTEST_FILES = {
    "README.md": "# index\n\n| symptom | go |\n|---|---|\n"
                 "| a | x.md \u00a7 **M1** |\n| b | x.md \u00a7 **M2** |\n"
                 "| c | x.md \u00a7 **M99** |\n",
    "x.md": "## M1 first\n\n## M2 second\n\n## M3 third\n",
}


def selftest():
    import tempfile
    tmp = tempfile.mkdtemp(prefix="casebook_selftest_")
    for fn, body in SELFTEST_FILES.items():
        with io.open(os.path.join(tmp, fn), "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
    idx = os.path.join(tmp, "README.md")
    res = scan(tmp, idx)
    ok_entries = len(res["entries"]) == 3
    ok_cov = abs(res["coverage"] - 66.666) < 0.1
    ok_phantom = res["phantom"] == ["M99"]
    for label, ok in (("entries counted (3)", ok_entries),
                      ("coverage 2/3 = 66.7%", ok_cov),
                      ("phantom M99 detected", ok_phantom)):
        print("  selftest %-24s %s" % (label, "PASS" if ok else "FAIL"))
    bad = 0 if (ok_entries and ok_cov and ok_phantom) else 1
    print("  selftest: %s" % ("PASS" if bad == 0 else "FAIL"))
    return bad


def main(argv):
    if "--selftest" in argv:
        return selftest()
    pit_dir = None
    index = None
    min_cov = 0.0
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--index":
            i += 1
            index = argv[i]
        elif a == "--min-coverage":
            i += 1
            min_cov = float(argv[i])
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif a.startswith("-"):
            print("unknown option %s (see --help)" % a, file=sys.stderr)
            return 2
        else:
            pit_dir = a
        i += 1
    if not pit_dir:
        print(__doc__)
        return 2
    if not os.path.isdir(pit_dir):
        print("%s is not a directory" % pit_dir, file=sys.stderr)
        return 2
    index_path = find_index(pit_dir, index)
    res = scan(pit_dir, index_path)
    phantom, coverage = report(pit_dir, index_path, res, min_cov)
    if phantom:
        return 1
    if coverage + 1e-9 < min_cov:
        print("coverage %.1f%% is below --min-coverage %.1f%%" % (coverage, min_cov))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
