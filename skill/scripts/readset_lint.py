#!/usr/bin/env python3
"""readset_lint.py -- a gate must read the fields it judges.  Check that, offline.

WHY THIS EXISTS (the failure that produced it)
    A reference-quality gate judged `refq_state`, but `refq_state` was not in the tuple the
    dump function actually read.  `value("refq_state")` therefore returned None, `None != 0`
    is true, and the gate refused every reference for ever.  From the outside that is
    indistinguishable from a dirty reference board, so an operator cleaned a clean board
    repeatedly.  The station's own word said PASS; the gate said FAIL.

    The fix was one line.  The durable fix is this check: a gate's inputs are a set drawn
    from a declared read set, and "used but not declared" must fail a test, not a bench run.

WHAT IT CHECKS
    1. USES    a field name passed to a reader call -- value()/get()/read()/field()/col()
               with a single string argument -- must appear in some declared name set;
    2. DECLARED name sets are assignments to an ALL_CAPS name (or to a name you pass with
               --decl) whose right-hand side is a tuple/list/set of string literals;
    3. optional --strict also reports declared-but-never-used names (dead read slots).

    Tokens come from Python's `tokenize`, so comments and string contents cannot fool it.
    It is still a textual lint, not a type checker: it cannot see names built at run time
    (a name computed by f-string, a loop over a config file).  Those are exactly the cases
    where you should ALSO print each gate's input when the gate refuses (see the casebook,
    entry D6).

USAGE
    python readset_lint.py dl/host_qc/accept_range.py
    python readset_lint.py tool.py --decl ROW_WORDS --decl COLUMNS --strict
    python readset_lint.py --selftest

EXIT CODES
    0 clean | 1 findings | 2 usage or parse error

ASCII ONLY.  No project paths are baked in: pass the files.
"""
import io
import sys
import tokenize

READER_ATTRS = ("value",)      # narrow on purpose: see SCOPE below
DEFAULT_DECL_PREFIX = ""      # empty = accept any ALL_CAPS assigned name

# SCOPE, and why the default attribute list is one name long.
#     The first version of this lint treated value()/get()/read()/field()/col() alike and
#     reported eight findings on the project's own acceptance tool -- seven of them were
#     ordinary dict lookups (`rec.get("ok")`, `verdict.get("line")`) that have nothing to do
#     with a read set.  A checker that cries wolf gets switched off, which is the same
#     failure the Tcl linter in this directory records.  So: the default is `value` only,
#     and any extra attribute is opt-in with --attr for a tool whose reader is named
#     differently.  The check is supposed to be quiet when the code is right.


def _strings_in(expr_tokens):
    return [t.string[1:-1] for t in expr_tokens
            if t.type == tokenize.STRING and len(t.string) >= 2 and t.string[0] in "'\""]


def scan_source(text, attrs=READER_ATTRS):
    """Return (declared_by_set, uses, notes) from Python source text.

    declared_by_set : {set_name: [field, ...]}   (named sets AND inline literal lists)
    uses            : [(field, lineno), ...]     fields a reader attribute was asked for
    notes           : [(lineno, text), ...]      reader calls whose argument is not a literal

    THREE SHAPES ARE RECOGNISED
        A.  NAME = ("a", "b")          a named read set
        B.  read(("a", "b"))           an inline literal list, i.e. a read set at the call
        C.  obj.value("a")             a use -- the name must exist in A or B somewhere

    Shape B is the one the first version missed, and the miss mattered: the acceptance tool
    it was pointed at reads its words inline (`st.read(("part_ref", "diff_ok", ...))`), so
    the lint reported eight false positives on correct code.  Recognising B is what makes
    the check usable on a tool that has no module-level word table at all.
    """
    toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    declared = {}
    uses = []
    notes = []
    n = len(toks)

    def matching(j):
        """Index of the delimiter closing the one at toks[j], or n-1."""
        opener = toks[j].string
        closer = {"(": ")", "[": "]", "{": "}"}.get(opener)
        depth = 0
        k = j
        while k < n:
            s = toks[k].string
            if s in "([{":
                depth += 1
            elif s in ")]}":
                depth -= 1
                if depth == 0 and s == closer:
                    return k
            k += 1
        return n - 1

    def literal_list(lo, hi):
        """Strings inside toks[lo:hi] if the range is only strings and punctuation."""
        strings = []
        for u in toks[lo:hi]:
            if u.type == tokenize.STRING:
                strings.append(u.string[1:-1])
            elif u.type == tokenize.OP and u.string in ",()[]{}":
                continue
            elif u.type in (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
                            tokenize.DEDENT, tokenize.COMMENT):
                continue
            else:
                return None
        return strings

    i = 0
    while i < n:
        t = toks[i]
        # shape A: NAME = ( ... )
        if t.type == tokenize.NAME and i + 2 < n and toks[i + 1].string == "=" \
                and toks[i + 2].string in "([{":
            k = matching(i + 2)
            strings = literal_list(i + 3, k)
            if strings:
                declared.setdefault(t.string, []).extend(strings)
            i = k + 1
            continue
        # shapes B and C: a bracketed group, and what precedes it
        if t.type == tokenize.OP and t.string in "([{":
            k = matching(i)
            strings = literal_list(i + 1, k)
            prev = toks[i - 1] if i > 0 else None
            prev_name = prev.string if (prev is not None and prev.type == tokenize.NAME) else ""
            if strings is None:
                if prev_name in attrs:
                    notes.append((t.start[0], "reader attribute %r called with a non-literal "
                                              "argument: the check cannot resolve it"
                                  % prev_name))
            elif prev_name in attrs:
                for s in strings:
                    uses.append((s, toks[i + 1].start[0] if i + 1 < k else t.start[0]))
            elif strings:
                declared.setdefault("inline@%d" % t.start[0], []).extend(strings)
            i = k + 1
            continue
        i += 1
    return declared, uses, notes


def analyse(path, decl_names=None, strict=False, attrs=READER_ATTRS, pool=None):
    """Judge one file.  `pool` is a set of names declared ANYWHERE in the run.

    THE POOL EXISTS BECAUSE A READ SET CAN LIVE IN ANOTHER MODULE.  The acceptance tool
    reads `eg_thr_used` from a word table defined in a sibling module, so judging that file
    alone reports a correct program as broken -- the crying-wolf failure again.  Pass the
    module that declares the words and both files are scanned together.
    """
    with io.open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    declared, uses, notes = scan_source(text, attrs)
    if decl_names:
        keep = {k: v for k, v in declared.items() if k in decl_names}
        if not keep:
            return ["no declared set named %s (found: %s)"
                    % (", ".join(decl_names),
                       ", ".join(sorted(declared)) or "none")], {}
        declared = keep
    known = set()
    for names in declared.values():
        known.update(names)
    known |= (pool or set())
    problems = []
    seen = set()
    for field, line in uses:
        if field not in known and (field, line) not in seen:
            seen.add((field, line))
            problems.append("line %d: reader call uses %r, which no declared read set "
                            "contains -- the gate will see None and call it a FAIL"
                            % (line, field))
    if strict:
        used = {f for f, _ in uses}
        for set_name, names in sorted(declared.items()):
            for nm in names:
                if nm not in used:
                    problems.append("declared but never read: %s / %r" % (set_name, nm))
    named = [k for k in declared if not k.startswith("inline@")]
    stats = {"declared": named,
             "inline_sets": len(declared) - len(named),
             "fields": len(known), "uses": len(uses), "notes": notes}
    return problems, stats


SELFTEST_CLEAN = '''\
ROW_WORDS = ("a", "b", "refq_state")
def judge(d):
    return d.value("refq_state") == 0 and d.value("a") == 1
'''

SELFTEST_BROKEN = '''\
ROW_WORDS = ("a", "b")
def judge(d):
    v = d.value("refq_state")        # not in ROW_WORDS: the D6 failure
    return v == 0
'''

SELFTEST_INLINE = '''\
def read_words():
    return None
def judge(st):
    r = st.read(("part_ref", "diff_ok"))     # inline read set: shape B
    return r.value("part_ref") == 0 and r.value("refq_state") == 0
'''


def selftest():
    import os
    import tempfile
    cases = [("clean_named_set.py", SELFTEST_CLEAN, 0),
             ("undeclared_word.py", SELFTEST_BROKEN, 1),
             ("inline_set_missing.py", SELFTEST_INLINE, 1)]
    bad = 0
    tmp = tempfile.mkdtemp(prefix="readset_selftest_")
    for name, body, want in cases:
        p = os.path.join(tmp, name)
        with io.open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        problems, _stats = analyse(p)
        got = 1 if problems else 0
        ok = got == want
        bad += 0 if ok else 1
        print("  selftest %-22s want exit %d, got %d  %s"
              % (name, want, got, "PASS" if ok else "FAIL"))
        if problems and not ok:
            for pr in problems:
                print("      %s" % pr)
    print("  selftest: %d/%d cases passed" % (len(cases) - bad, len(cases)))
    return 0 if bad == 0 else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    decl = []
    attrs = list(READER_ATTRS)
    strict = False
    files = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--decl":
            i += 1
            decl.append(argv[i])
        elif a == "--attr":
            i += 1
            attrs = [x.strip() for x in argv[i].split(",") if x.strip()]
        elif a == "--strict":
            strict = True
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
    # pass 1: every declaration in the run, pooled (a read set may live in a sibling module)
    pool = set()
    for path in files:
        try:
            with io.open(path, encoding="utf-8", errors="replace") as f:
                declared, _u, _n = scan_source(f.read(), tuple(attrs))
        except Exception:
            continue
        if decl:
            declared = {k: v for k, v in declared.items() if k in decl}
        for names in declared.values():
            pool.update(names)
    # pass 2: judge each file against the pool
    total = 0
    for path in files:
        try:
            problems, stats = analyse(path, decl or None, strict, tuple(attrs), pool)
        except Exception as exc:                     # parse error is a finding, not a crash
            print("%s: cannot scan (%s)" % (path, exc))
            total += 1
            continue
        print("%s: named sets %d (%s), %d inline literal sets, %d declared fields, "
              "%d reader calls"
              % (path, len(stats.get("declared") or []),
                 ",".join(stats.get("declared") or ["-"]),
                 stats.get("inline_sets", 0), stats.get("fields", 0),
                 stats.get("uses", 0)))
        for pr in problems:
            print("  %s" % pr)
        for line, txt in stats.get("notes") or []:
            print("  note line %d: %s" % (line, txt))
        total += len(problems)
    print("FINDINGS: %d" % total)
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
