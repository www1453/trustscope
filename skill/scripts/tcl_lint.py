#!/usr/bin/env python3
"""Mechanical self-check for xsdb/Vivado Tcl scripts, run BEFORE the script is.

Three failure modes have actually cost runs in this project:

  * non-ASCII bytes in a Tcl script.  On a Chinese Windows, Vivado's Tcl console
    reads the file as GBK; UTF-8 Chinese bytes get misdecoded and can eat a
    quote or brace, producing an error that looks nothing like the cause.
  * unbalanced or MISPLACED braces/brackets.  A single `]` typed inside a brace
    group instead of after it produced `missing close-bracket` at run time --
    e.g. `return [expr {($a & 0xFF)]}` instead of `... )}]`.
  * a TRAILING `#` comment.  Tcl only starts a comment where a command would
    start.  `WM $MB 0x0  # seed` is not a commented statement, it is a call to
    WM with three arguments, and it fails with `wrong # args: should be "WM a v"`
    -- an error naming the proc, not the comment.  This check exists because that
    exact line was written, and because an earlier version of THIS LINTER
    treated the trailing `#` as a comment and therefore passed the broken file.
    A checker that shares the author's misconception confirms it instead of
    catching it.

SCOPE OF EACH CHECK -- this matters as much as the checks themselves.
    The non-ASCII scan is meaningful for every text file this project drives
    through a Windows toolchain.  The brace/bracket and trailing-`#` rules are
    TCL SYNTAX rules and are WRONG for PowerShell, Python, C and linker scripts,
    where `#` or a trailing comment is perfectly legal.  Applying them there
    produced pure noise, and noise in a checker is how a checker gets ignored.
    So each rule runs only on the file type it is true for, and the result line
    says which rules were applied.

This is a cheap textual check, not a parser: it counts delimiters outside of
comments and quoted strings and flags suspicious ordering, which catches exactly
the typos above.  It cannot prove a script is correct.

Usage:  tcl_lint.py file1.tcl [file2.py ...]
Exit code 0 = clean, 1 = findings.
"""
import sys


def check(path):
    with open(path, "rb") as f:
        raw = f.read()
    bad = [(i, b) for i, b in enumerate(raw) if b > 127]
    text = raw.decode("utf-8", errors="replace")

    # which rules are even true for this file type?
    low = path.lower()
    is_tcl = low.endswith(".tcl")
    is_ps1 = low.endswith(".ps1")
    is_py = low.endswith(".py")
    is_c = low.endswith((".c", ".h", ".s", ".ld"))
    tcl_rules = is_tcl

    findings = []
    if bad:
        first = bad[0][0]
        line = raw[:first].count(b"\n") + 1
        hexs = " ".join("%02X" % b for _, b in bad[:8])
        findings.append("non-ASCII bytes (first at line %d: %s)" % (line, hexs))

    if not tcl_rules:
        # Deliberately skip the Tcl syntax rules here: a trailing '#' is a legal
        # comment in PowerShell, Python, C and linker scripts, so flagging it
        # there is a false positive.  A checker that cries wolf gets ignored.
        return findings, ("bytes only" if not bad else "bytes only (non-ASCII)")

    depth_brace = depth_brack = 0
    min_brace = min_brack = 0
    in_quote = False
    escaped = False
    trailing_comment_lines = []
    for ln, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue          # a genuine comment: comment runs to end of line
        prev_sig = ""         # last significant (non-space) char seen this line
        for ch in line:
            if escaped:
                escaped = False
                prev_sig = ch
                continue
            if ch == "\\":
                escaped = True
                prev_sig = ch
                continue
            if ch == '"':
                in_quote = not in_quote
                prev_sig = ch
                continue
            if in_quote:
                continue
            if ch == "#" and depth_brace == 0 and depth_brack == 0:
                # A '#' here is only a real comment if this is where a command
                # would start.  After ordinary text it is just another argument.
                if prev_sig not in ("", ";", "{", "["):
                    trailing_comment_lines.append(ln)
                break
            if ch not in (" ", "\t"):
                prev_sig = ch
            if ch == "{":
                depth_brace += 1
            elif ch == "}":
                depth_brace -= 1
            elif ch == "[":
                depth_brack += 1
            elif ch == "]":
                depth_brack -= 1
            min_brace = min(min_brace, depth_brace)
            min_brack = min(min_brack, depth_brack)
    if trailing_comment_lines:
        shown = ", ".join(str(x) for x in trailing_comment_lines[:6])
        findings.append(
            "trailing '#' comment on line(s) %s -- Tcl treats it as extra "
            "arguments, not as a comment" % shown)
    if depth_brace != 0:
        findings.append("unbalanced braces: net %+d" % depth_brace)
    if depth_brack != 0:
        findings.append("unbalanced brackets: net %+d" % depth_brack)
    if min_brace < 0:
        findings.append("a '}' appears before its '{'")
    if min_brack < 0:
        findings.append("a ']' appears before its '['")

    # --- `for` arity ---------------------------------------------------------
    # WHY THIS RULE EXISTS: a script had
    #     for {set i 0} {[incr i] <= $n} {        <- only 3 args, no `next`
    # Tcl rejects that AT EXECUTION TIME ("wrong # args: should be
    # \"for start test next command\""), never at parse time, so the file looked
    # fine.  Because the statement right before it was `stop`, every abort left
    # the CPU HALTED -- which showed up as "the frame counter is not advancing"
    # and cost three rounds of debugging aimed at the wrong thing.  Every brace
    # was balanced, so none of the rules above fired.  A lint that stays quiet on
    # a script that cannot run is worse than no lint: it manufactures confidence.
    #
    # The rule: a `for` command has four brace groups -- start / test / next /
    # body.  Counting "groups on the line" is NOT enough, and the first version of
    # this rule was silently dead because of it: the bug being hunted is a
    # MULTI-LINE for whose body brace opens on the header line, so the line ends
    # at brace depth > 0 and a naive "skip multi-line" test skipped exactly the
    # case the rule exists for.  A dead guard is worse than no guard -- it
    # manufactures confidence.  (Found by a negative control: the rule was run
    # against the known-bad input and stayed silent.)
    #
    # Correct count: groups that CLOSE back at depth 0, plus the one still open
    # at end of line (that one is the body).
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line.startswith("for "):
            continue
        closed, depth, started = 0, 0, False
        for ch in line:
            if ch == "{":
                if depth == 0:
                    started = True
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    closed += 1
        if not started:
            continue
        total = closed + (1 if depth > 0 else 0)
        if depth < 0:
            continue  # brace-balance rule already reports this
        if total != 4:
            findings.append(
                "line %d: `for` has %d brace group(s), needs 4 "
                "(start / test / next / body) -- Tcl fails this at RUN time, "
                "not parse time" % (lineno, total))

    # --- brackets inside a double-quoted string -----------------------------
    # WHY THIS RULE EXISTS (third member of the same family as the `for` rule):
    #   A capture script had
    #       L [format "  [%3d.%1d s]  frame %2d ..." ...]
    #   Inside a double-quoted Tcl string, [...] is COMMAND SUBSTITUTION, so Tcl
    #   tried to run a command named "%3d.%1d s", raised, and the script died --
    #   AFTER the frame had been dumped but BEFORE it was logged.  Symptoms:
    #   the .bin existed, the log had no line for it, exit code 1, and the CPU
    #   was left HALTED (the trailing `con` was never reached), which then made
    #   the NEXT run abstain with "frame counter not advancing".
    #
    #   The brace/bracket balance rules above did NOT catch it: the brackets were
    #   perfectly balanced.  A balanced bracket can still be a command whose name
    #   is nonsense -- balance is a shape check, not a meaning check.
    #
    # What is reported: a bracket pair that opens inside a double-quoted string
    # and whose content cannot possibly be a command name -- it contains '%',
    # or starts with a digit/sign.  Deliberately narrow: `[expr ...]`,
    # `[get_ports ...]`, `[format ...]` inside strings are legitimate and common,
    # so a broad rule would bury the real signal in noise -- and a rule that
    # cries wolf is a rule people turn off.
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw
        i = 0
        in_str = False
        while i < len(line):
            ch = line[i]
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = not in_str
                i += 1
                continue
            if ch == "[" and in_str:
                depth = 1
                j = i + 1
                while j < len(line) and depth > 0:
                    if line[j] == "\\":
                        j += 2
                        continue
                    if line[j] == "[":
                        depth += 1
                    elif line[j] == "]":
                        depth -= 1
                    j += 1
                if depth == 0:
                    inner = line[i + 1:j - 1].strip()
                    # Only the FIRST WORD decides.  The first version tested the
                    # whole content for '%', which false-positived on
                    #     puts $tr "\[[clock format [clock seconds] -format %H:%M:%S]\] $m"
                    # -- a legitimate command substitution whose ARGUMENT happens
                    # to contain '%'.  That is exactly the "cries wolf" failure
                    # mode this rule's own comment warns about: a linter people
                    # turn off catches nothing.  A real format literal starts with
                    # the format spec itself, so the first word is what matters.
                    first = inner.split()[0] if inner.split() else ""
                    if first and (("%" in first) or first[0].isdigit() or first[0] in "+-"):
                        findings.append(
                            "line %d: '[' inside a double-quoted string looks "
                            "like a format literal, but Tcl treats it as COMMAND "
                            "SUBSTITUTION (it would try to run `%s`). "
                            "Use parentheses, or escape as \\[ \\]." % (lineno, inner[:30]))
                i = j
                continue
            i += 1
    return findings, "tcl rules + bytes"


def main():
    rc = 0
    for path in sys.argv[1:]:
        f, scope = check(path)
        if f:
            rc = 1
            for item in f:
                print("%s: %s [%s]" % (path, item, scope))
        else:
            print("%s: OK [%s]" % (path, scope))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
