#!/usr/bin/env python3
"""wordmap_check.py -- catch two names sharing one address BEFORE the board does.

WHY THIS EXISTS
    A mailbox/register map is a namespace with no compiler.  Two `#define`s can name the same
    word and nothing complains: both reads return, both look plausible, and the value you get
    is the other feature's.  It has happened here as a genuine collision (a new counter landed
    on an existing focus value at the same index, read 192, and the number was believed for a
    while) and as a near miss (a new field was allocated from memory instead of from the free
    table, which is what the two-agents-one-file case in the casebook is about).

    The compiler checks types, not addresses.  This checks addresses.

WHAT IT REPORTS
    duplicate index   two or more names at the same address  -> exit 1
    split name        one name defined with two addresses    -> exit 1
    gaps              (--gaps) unused indices inside the range, informational

USAGE
    python wordmap_check.py ps_ui/main.c                       # C #define map
    python wordmap_check.py map.csv --format csv              # name,index[,comment]
    python wordmap_check.py words.tcl --format kv             # NAME = 0x10  /  set NAME 16
    python wordmap_check.py --selftest

    Formats: auto (default), define, kv, csv.  Lines that do not match are ignored, so a
    source file can be pointed at directly; that also means a typo'd definition is ignored
    rather than reported -- so also run it on the map file you actually ship.

    `--base` (default 0) is subtracted before the gap report, for maps that are byte offsets
    into a region rather than absolute addresses.

EXIT CODES
    0 clean | 1 collisions/splits | 2 usage/parse error

LIMITS (which decide whether this is worth running)
    * It compares NAMES to NUMBERS.  A field that is a byte offset into a word, or a struct
      member, is not modelled -- if your map mixes units, convert before checking.
    * The same name in an unnamed scope (a local) will look like a split name; give the
      shipped map only, not every file in the tree.

ASCII ONLY.
"""
import io
import re
import sys

_TAIL = r"(?=\s|$|/\*|//)"          # a trailing comment is allowed; anything else is not
RE_DEFINE = re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)\s+\(?\s*"
                       r"(0[xX][0-9a-fA-F]+|\d+)\s*[uUlL]*\s*\)?" + _TAIL)
RE_KV_SET = re.compile(r"^\s*set\s+([A-Za-z_]\w*)\s+(0[xX][0-9a-fA-F]+|\d+)" + _TAIL)
RE_KV_ASSIGN = re.compile(r"^\s*([A-Za-z_]\w*)\s*[=:]\s*"
                          r"(0[xX][0-9a-fA-F]+|\d+)\s*[uUlL]*" + _TAIL)
RE_IDENT = re.compile(r"^[A-Za-z_]\w*$")
GAP_SPAN_LIMIT = 200000        # see the note in check(): a base address is not a slot


def to_int(s):
    return int(s, 16) if s.lower().startswith("0x") else int(s, 10)


def parse(path, fmt="auto"):
    """Return [(name, addr, lineno), ...]."""
    out = []
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            s = line.rstrip("\n")
            m = None
            order = []
            if fmt in ("auto", "define"):
                order.append("define")
            if fmt in ("auto", "kv"):
                order.append("kv")
            if fmt in ("auto", "csv"):
                order.append("csv")
            for kind in order:
                if kind == "define":
                    m = RE_DEFINE.match(s)
                elif kind == "kv":
                    m = RE_KV_SET.match(s) or RE_KV_ASSIGN.match(s)
                elif kind == "csv":
                    if "," not in s or s.lstrip().startswith("#"):
                        m = None
                        continue
                    parts = [p.strip() for p in s.split(",")]
                    if len(parts) < 2 or not RE_IDENT.match(parts[0]):
                        m = None
                        continue
                    try:
                        addr = to_int(parts[1])
                    except ValueError:
                        m = None
                        continue
                    out.append((parts[0], addr, lineno))
                    m = None
                    break
                if m:
                    out.append((m.group(1), to_int(m.group(2)), lineno))
                    break
    return out


def check(entries, base=0, gaps=False):
    problems = []
    notes = []
    by_addr = {}
    by_name = {}
    for name, addr, lineno in entries:
        by_addr.setdefault(addr, []).append((name, lineno))
        by_name.setdefault(name, []).append((addr, lineno))
    for addr in sorted(by_addr):
        names = by_addr[addr]
        uniq = sorted({n for n, _ln in names})
        if len(uniq) > 1:
            problems.append("address %d (0x%X) is claimed by %d names: %s"
                            % (addr, addr, len(uniq),
                               ", ".join("%s@%d" % (n, ln) for n, ln in names
                                         if n in uniq)))
    for name in sorted(by_name):
        addrs = by_name[name]
        uniq = {a for a, _ in addrs}
        if len(uniq) > 1:
            problems.append("name %s is defined %d times with DIFFERENT values: %s"
                            % (name, len(addrs),
                               ", ".join("%d@%d" % (a, ln) for a, ln in addrs)))
        elif len(addrs) > 1:
            # the same name re-defined to the same address: noise, not a collision
            notes.append("name %s is defined %d times to the same value %d (%s)"
                         % (name, len(addrs), addrs[0][0],
                            ", ".join("line %d" % ln for _a, ln in addrs)))
    info = ""
    if gaps and by_addr:
        lo = min(by_addr) - base
        hi = max(by_addr) - base
        span = hi - lo + 1
        # A "map" that also contains a base ADDRESS (0x43C00000) would make the gap list a
        # billion entries and hang the tool.  Bound it and say so rather than die silently.
        if span > GAP_SPAN_LIMIT:
            info = ("range %d..%d is %d slots -- too wide for a gap report (limit %d); "
                    "pass --base or drop --gaps" % (lo, hi, span, GAP_SPAN_LIMIT))
        else:
            missing = [i for i in range(lo, hi + 1) if (i + base) not in by_addr]
            info = "range %d..%d, %d unused: %s" % (
                lo, hi, len(missing),
                " ".join(str(x) for x in missing[:20]) + (" ..." if len(missing) > 20 else ""))
    return problems, info, notes


SELFTEST_CLEAN = """\
#define MB_A 10u
#define MB_B 11u
#define MB_C 0x0C
"""

SELFTEST_COLLIDE = """\
#define MB_ARM_N 135u
#define MB_FOCUS 135u     /* the collision that produced this tool */
#define MB_X 140u
"""

SELFTEST_SPLIT = """\
MB_A = 10
MB_A = 12
"""


def selftest():
    import os
    import tempfile
    tmp = tempfile.mkdtemp(prefix="wordmap_selftest_")
    cases = [("clean.h", SELFTEST_CLEAN, "define", 0),
             ("collide.h", SELFTEST_COLLIDE, "define", 1),
             ("split.tcl", SELFTEST_SPLIT, "kv", 1)]
    bad = 0
    for name, body, fmt, want in cases:
        p = os.path.join(tmp, name)
        with io.open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        entries = parse(p, fmt)
        problems, _info, _notes = check(entries)
        got = len(problems)
        ok = got == want
        bad += 0 if ok else 1
        print("  selftest %-12s %d entries, want %d problem(s), got %d  %s"
              % (name, len(entries), want, got, "PASS" if ok else "FAIL"))
        if not ok:
            for pr in problems:
                print("      %s" % pr)
    print("  selftest: %d/%d cases passed" % (len(cases) - bad, len(cases)))
    return 0 if bad == 0 else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    fmt = "auto"
    base = 0
    gaps = False
    prefixes = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--format":
            i += 1
            fmt = argv[i]
        elif a == "--base":
            i += 1
            base = to_int(argv[i])
        elif a == "--prefix":
            i += 1
            prefixes.append(argv[i])
        elif a == "--gaps":
            gaps = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif a.startswith("-"):
            print("unknown option %s (see --help)" % a, file=sys.stderr)
            return 2
        else:
            files.append(a)
        i += 1
    if not files:
        print(__doc__)
        return 2
    total = 0
    for path in files:
        try:
            entries = parse(path, fmt)
        except Exception as exc:
            print("%s: cannot read (%s)" % (path, exc), file=sys.stderr)
            total += 1
            continue
        n_all = len(entries)
        if prefixes:
            entries = [e for e in entries
                       if any(e[0].startswith(p) for p in prefixes)]
        problems, info, notes = check(entries, base, gaps)
        print("%s: %d definitions parsed, %d in scope%s, %d distinct addresses"
              % (path, n_all, len(entries),
                 (" (" + ",".join(prefixes) + ")") if prefixes else "",
                 len({e[1] for e in entries})))
        if info:
            print("  %s" % info)
        for nt in notes:
            print("  note %s" % nt)
        for pr in problems:
            print("  %s" % pr)
        total += len(problems)
    print("FINDINGS: %d" % total)
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
