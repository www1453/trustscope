#!/usr/bin/env python3
"""run_selftests.py -- prove every script in this directory still does its job.

WHY THIS EXISTS
    A validation script that has never been run on a known-bad input is a script that has
    never been shown to fail.  This project spent real time on checkers that returned "pass"
    for everything (casebook D2) and on a lint that shared its author's misconception
    (the Tcl linter's own docstring records it), so every script here carries a --selftest
    with a KNOWN-BAD fixture, and this runner executes all of them in one command.

    It also covers the one script that has no --selftest flag (tcl_lint.py, kept as a
    verbatim copy of the project's linter): a fixture pair is generated here instead.

USAGE
    python run_selftests.py            # all scripts, quiet on pass
    python run_selftests.py -v         # show each script's own output too

EXIT CODES
    0 all passed | 1 at least one failed | 2 a script is missing

ASCII ONLY.
"""
import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

SELFTESTED = [
    ("readset_lint.py", "a gate that reads a word outside its read set fails the lint"),
    ("null_floor.py", "a null floor above the signal is FAIL, a separable one is PASS"),
    ("wordmap_check.py", "two names on one address is a finding, a clean map is not"),
    ("casebook_index.py", "entries are counted, and a phantom index reference is caught"),
    ("leak_scan.py", "a GBK-encoded needle is found; a clean tree is reported clean"),
]


def run(cmd, verbose):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    if verbose:
        for line in out.splitlines():
            print("      | %s" % line)
    return p.returncode, out


def tcl_lint_fixture(script, verbose):
    """tcl_lint.py takes file arguments and returns 1 on findings.  Give it one of each."""
    tmp = tempfile.mkdtemp(prefix="tcl_lint_selftest_")
    good = os.path.join(tmp, "good.tcl")
    bad = os.path.join(tmp, "bad.tcl")
    with io.open(good, "w", encoding="ascii", newline="\n") as f:
        f.write("puts \"hello\"\nset x [expr {1 + 1}]\n")
    # a non-ASCII byte in a comment: the exact thing the rule exists for
    with io.open(bad, "wb") as f:
        f.write(b"# \xe5\x8f\x8c\xe7\x9b\xae comment in utf-8\nputs \"hi\"\n")
    rc_good, _o = run([sys.executable, script, good], verbose)
    rc_bad, _o = run([sys.executable, script, bad], verbose)
    ok = (rc_good == 0 and rc_bad == 1)
    detail = "clean=exit %d (want 0), non-ascii=exit %d (want 1)" % (rc_good, rc_bad)
    return ok, detail


def main(argv):
    verbose = "-v" in argv or "--verbose" in argv
    missing = [n for n, _d in SELFTESTED
               if not os.path.exists(os.path.join(HERE, n))]
    if not os.path.exists(os.path.join(HERE, "tcl_lint.py")):
        missing.append("tcl_lint.py")
    if missing:
        print("MISSING: %s" % ", ".join(missing))
        return 2

    results = []
    for name, purpose in SELFTESTED:
        path = os.path.join(HERE, name)
        rc, out = run([sys.executable, path, "--selftest"], verbose)
        detail = "exit %d" % rc
        if rc != 0:
            tail = [ln for ln in out.splitlines() if "FAIL" in ln][:3]
            detail = "; ".join(tail) or detail
        results.append((name, purpose, rc == 0, detail))

    ok, detail = tcl_lint_fixture(os.path.join(HERE, "tcl_lint.py"), verbose)
    results.append(("tcl_lint.py", "non-ASCII is caught, clean Tcl passes", ok, detail))

    print("")
    print("%-20s %-6s %s" % ("script", "result", "what it proves"))
    print("-" * 96)
    for name, purpose, passed, detail in results:
        print("%-20s %-6s %s" % (name, "PASS" if passed else "FAIL", purpose))
        if not passed:
            print("%-27s %s" % ("", detail))
    n_fail = sum(1 for r in results if not r[2])
    print("-" * 96)
    print("%d/%d passed" % (len(results) - n_fail, len(results)))
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
