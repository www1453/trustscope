#!/usr/bin/env python3
"""leak_scan.py -- find what must not ship, in a tree that mixes encodings.

WHY THIS EXISTS (the sweep that could not fail for the right reason)
    A checklist recorded an institution name on one line of one markdown file.  A PowerShell
    `Select-String` sweep with UTF-8 patterns over the same tree reported ZERO hits -- because
    that file is not UTF-8: it decodes as GBK, and UTF-8 bytes never match GBK bytes.  A scan
    that cannot fail for the right reason is not a scan, it is a formality that returns clean.

    So this reads bytes, decodes them three ways (utf-8, utf-8-sig, gbk), and searches every
    decoding that succeeds.  A file that decodes under several schemes is searched under all.

WHAT IT LOOKS FOR
    1. identity needles: institution, student/teacher identifiers, and the words around them
       (overridden or extended with --needles FILE, one needle per line, '#' comments);
    2. personal absolute paths in file names: any path segment matching C:\\Users\\... .
       The file CONTENT is not scanned for these -- a build log legitimately contains paths,
       a shipped source file does not, and that distinction is the whole point of a path scan.

    Binary files are skipped BY EXTENSION, not by a decode failure, so a binary that happens
    to contain the bytes is reported as "skipped", never silently counted as clean.

USAGE
    python leak_scan.py .                       # the current tree
    python leak_scan.py skill report --needles my_needles.txt
    python leak_scan.py --selftest

EXIT CODES
    0 no hits | 1 hits | 2 usage error

THE LIMITS THAT MATTER
    * It cannot find a leak it has no needle for.  Run it with your own contest's exclusion
      list, not just the defaults.
    * It does not judge: a hit is a line to read, not a verdict.  The output shows the line.
    * Archive files (.zip/.rar/.docx/.pdf) are skipped by extension, so a leak inside a
      packaged deliverable is invisible here.  Unpack, or scan after extraction.

ASCII ONLY in this source.  The needles are written as escapes and split literals so that
this scanner's own file does not match its own needles -- otherwise the first run in this
repository reports the scanner.
"""
import io
import os
import sys

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "backups"}
SKIP_EXT = {".bin", ".elf", ".bit", ".png", ".jpg", ".jpeg", ".gif", ".zip", ".rar", ".7z",
            ".xsa", ".avi", ".mp4", ".npz", ".pdf", ".docx", ".pptx", ".xlsx", ".dmp",
            ".ltx", ".obj", ".o", ".a", ".so", ".exe", ".dll", ".pack", ".idx",
            ".pyc", ".dcp", ".jou", ".wdb", ".vcd", ".raw"}

# Identity needles, as '\uXXXX' escapes so this source stays ASCII.
_NEEDLES_ASCII = [
    "\u5b66\u6821", "\u5927\u5b66", "\u5b66\u9662", "\u5b66\u53f7", "\u73ed\u7ea7",
    "\u6bd5\u4e1a", "\u5bfc\u5e08", "\u6307\u5bfc\u8001\u5e08", "\u672c\u79d1\u9662",
    "\u5f85\u6bd5\u4e1a", "\u8bba\u6587",
    "student" + " id", "advi" + "sor", "advi" + "ser",
]
# The English institution words are SPLIT so that this file does not contain them whole.
_NEEDLES_ASCII += [
    "uni" + "versity", "col" + "lege", "sch" + "ool",
]

PATH_NEEDLE = "c:" + "\\" + "users" + "\\"


def load_needles(path):
    out = []
    with io.open(path, encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#"):
                out.append(s)
    return out


def decode_variants(raw):
    out = []
    for enc in ("utf-8", "utf-8-sig", "gbk"):
        try:
            out.append((enc, raw.decode(enc)))
        except Exception:
            pass
    return out


def scan(roots, needles, skip_dirs=None, skip_ext=None, path_scan=True):
    skip_dirs = SKIP_DIRS if skip_dirs is None else skip_dirs
    skip_ext = SKIP_EXT if skip_ext is None else skip_ext
    hits = []
    path_hits = []
    scanned = 0
    skipped_binary = 0
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in skip_dirs]
            for fn in filenames:
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p)
                if path_scan and PATH_NEEDLE in rel.lower():
                    path_hits.append(rel)
                ext = os.path.splitext(fn)[1].lower()
                if ext in skip_ext:
                    skipped_binary += 1
                    continue
                try:
                    raw = io.open(p, "rb").read()
                except Exception:
                    continue
                decs = decode_variants(raw)
                if not decs:
                    skipped_binary += 1
                    continue
                scanned += 1
                seen = set()
                for enc, text in decs:
                    low = text.lower()
                    for needle in needles:
                        if needle.lower() in low:
                            for i, line in enumerate(text.splitlines(), 1):
                                if needle.lower() in line.lower() and (rel, i) not in seen:
                                    seen.add((rel, i))
                                    hits.append((rel, i, enc, needle, line.strip()[:110]))
    return {"hits": hits, "path_hits": path_hits,
            "scanned": scanned, "skipped": skipped_binary}


def _printable(s):
    """The console here is a legacy codepage; a glyph it cannot encode must not kill the
    report, because a report that dies mid-way looks exactly like a scan that found nothing
    after that point."""
    try:
        s.encode("gbk")
        return s
    except UnicodeEncodeError:
        return s.encode("gbk", "replace").decode("gbk")


def report(res):
    print("scanned %d text files, skipped %d binary by extension"
          % (res["scanned"], res["skipped"]))
    print("content HITS: %d" % len(res["hits"]))
    for rel, i, enc, needle, line in sorted(res["hits"]):
        print("  %s:%d  [%s]  %s" % (rel, i, enc, _printable(line)))
    print("path HITS: %d" % len(res["path_hits"]))
    for rel in sorted(res["path_hits"]):
        print("  %s" % _printable(rel))
    return len(res["hits"]) + len(res["path_hits"])


NEEDLE_SELFTEST = "\u6d4b\u8bd5\u6807\u8bb0"          # 'test marker', not an identity term


def selftest():
    import tempfile
    tmp = tempfile.mkdtemp(prefix="leak_scan_selftest_")
    clean = os.path.join(tmp, "clean.txt")
    leaky = os.path.join(tmp, "leaky.txt")
    with io.open(clean, "w", encoding="utf-8", newline="\n") as f:
        f.write("this file is clean\n")
    # written as GBK on purpose: this is the case the UTF-8-only sweep missed
    with io.open(leaky, "wb") as f:
        f.write(("header\n%s appears here\n" % NEEDLE_SELFTEST).encode("gbk"))
    res = scan([tmp], [NEEDLE_SELFTEST], path_scan=False)
    got = len(res["hits"])
    ok = got == 1 and res["hits"][0][0].endswith("leaky.txt")
    print("  selftest gbk-encoded needle found without utf-8 decode: %s"
          % ("PASS" if ok else "FAIL (%d hits)" % got))
    res2 = scan([tmp], ["\u4e0d\u5b58\u5728\u7684\u8bcd"], path_scan=False)
    ok2 = len(res2["hits"]) == 0
    print("  selftest clean tree reports zero hits:                    %s"
          % ("PASS" if ok2 else "FAIL"))
    return 0 if (ok and ok2) else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    roots = []
    needles = list(_NEEDLES_ASCII)
    needles_file = None
    path_scan = True
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--needles":
            i += 1
            needles_file = argv[i]
        elif a == "--no-path-scan":
            path_scan = False
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif a.startswith("-"):
            print("unknown option %s (see --help)" % a, file=sys.stderr)
            return 2
        else:
            roots.append(a)
        i += 1
    if needles_file:
        try:
            extra = load_needles(needles_file)
        except Exception as exc:
            print("cannot read needles %s: %s" % (needles_file, exc), file=sys.stderr)
            return 2
        needles = extra
    if not roots:
        roots = ["."]
    res = scan(roots, needles, path_scan=path_scan)
    n = report(res)
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
