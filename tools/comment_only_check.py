#!/usr/bin/env python3
"""Prove that an edit to HDL or Quartus files changed comments only.

For each file that differs between a base revision and the working tree (or
a second revision), compare what the tools see once comments are removed:

  .vhd .vhdl      VHDL: '--' comments removed outside string and character
                  literals; token streams compared.
  .sv .v .svh .vh SystemVerilog/Verilog: '//' and '/* */' comments removed
                  outside string literals; token streams compared. If
                  verilator is on PATH, the file is also run through
                  'verilator -E -P' (with --define for each macro given by
                  --qsf) and the preprocessed token streams are compared, which
                  catches a comment line slipped into a multi-line `define.
  .qsf .sdc .tcl  Tcl-style: lines whose first non-blank character is '#' and
                  blank lines are dropped; the remaining lines must be
                  identical and in the same order.

Comments that tools read as directives are kept as tokens, so adding,
removing or rewording one counts as a change: any comment whose text starts
with synthesis, synopsys, altera, pragma, translate_on/off, verilator,
lint_on/off, quartus, cadence, xilinx or intel (case-insensitive) followed
by blank space or the end of the comment ("Synthesis-only ..." is prose).

Any other file type that differs is reported as UNCHECKED (exit status 1),
unless --ignore matches it. Added and deleted files are reported and fail
the check unless their type is in --allow-new (for example .md or .py).

Usage:
  tools/comment_only_check.py --base 24235eb                 # working tree
  tools/comment_only_check.py --base 24235eb --head HEAD     # two commits
  tools/comment_only_check.py --base 24235eb --qsf GNET_Z1FULLR.qsf \\
      --allow-new .md,.py --ignore 'docs/*'
  tools/comment_only_check.py --base 24235eb rtl/zoom/zsg2.sv   # given files

Exit status 0 = every checked file is comment-only identical; 1 otherwise.
Self-test: tools/comment_only_check.py --self-test
"""

import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile

VHDL_EXT = {".vhd", ".vhdl"}
SV_EXT = {".sv", ".v", ".svh", ".vh"}
TCL_EXT = {".qsf", ".sdc", ".tcl"}

DIRECTIVE = re.compile(
    r"^\s*(synthesis|synopsys|altera|pragma|translate_on|translate_off|"
    r"verilator|lint_on|lint_off|quartus|cadence|xilinx|intel)(\s|$)",
    re.IGNORECASE,
)
TOKEN = re.compile(r'"(?:[^"\\\n]|\\.)*"|\w+|\S')


def _keep(comment_text):
    """Return a token for a directive comment, or None for a plain comment."""
    if DIRECTIVE.match(comment_text):
        return " /*DIRECTIVE:" + " ".join(comment_text.split()) + "*/ "
    return None


def strip_vhdl(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == '"':
                    if j + 1 < n and text[j + 1] == '"':
                        j += 2
                        continue
                    break
                if text[j] == "\n":
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
        elif c == "'" and i + 2 < n and text[i + 2] == "'":
            # character literal such as '0', '"' or '-'
            out.append(text[i:i + 3])
            i += 3
        elif c == "-" and i + 1 < n and text[i + 1] == "-":
            j = text.find("\n", i)
            if j < 0:
                j = n
            keep = _keep(text[i + 2:j])
            out.append(keep if keep else " ")
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def strip_sv(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j < 0:
                j = n
            keep = _keep(text[i + 2:j])
            out.append(keep if keep else " ")
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                j = n - 2
            body = text[i + 2:j]
            keep = _keep(body)
            # keep the line count so `define continuations stay comparable
            out.append(keep if keep else " " + "\n" * body.count("\n"))
            i = j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def tokens(text):
    return TOKEN.findall(text)


def tcl_lines(text):
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        lines.append(line.rstrip())
    return lines


def first_diff(a, b):
    for k, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return k
    return min(len(a), len(b))


def context(seq, k, width=8):
    return " ".join(seq[max(0, k - width):k + width])


def preprocess(text, defines, incdirs):
    vl = shutil.which("verilator")
    if not vl:
        return None
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "in.sv")
        with open(p, "w") as fh:
            fh.write(text)
        # build_id.v is written by the Quartus flow (sys/build_id.tcl); a stub
        # with a fixed date keeps PSX.sv preprocessable
        with open(os.path.join(td, "build_id.v"), "w") as fh:
            fh.write('`define BUILD_DATE "000000"\n')
        cmd = [vl, "-E", "-P", "--bbox-sys", "-Wno-fatal"]
        cmd += ["+define+%s=%s" % (k, v) for k, v in defines]
        cmd += ["-I" + os.path.abspath(d) for d in incdirs] + ["-I" + td]
        cmd.append(p)
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=td)
        if r.returncode != 0:
            msg = r.stderr.strip().splitlines()[0] if r.stderr.strip() else ""
            return "ERROR: " + msg.replace(td, "<tmp>")
        return r.stdout.replace(td, "<tmp>")


def qsf_macros(path):
    macros = []
    pat = re.compile(r'^\s*set_global_assignment\s+-name\s+VERILOG_MACRO\s+"([^"=]+)(?:=([^"]*))?"')
    with open(path) as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                macros.append((m.group(1), m.group(2) if m.group(2) is not None else "1"))
    return macros


def compare(path, old, new, defines, incdirs):
    """Return (status, detail); status in OK, CHANGED, UNCHECKED."""
    ext = os.path.splitext(path)[1].lower()
    if ext in VHDL_EXT:
        a, b = tokens(strip_vhdl(old)), tokens(strip_vhdl(new))
        if a != b:
            k = first_diff(a, b)
            return "CHANGED", "token %d: base [%s] new [%s]" % (k, context(a, k), context(b, k))
        return "OK", "%d tokens" % len(a)
    if ext in SV_EXT:
        a, b = tokens(strip_sv(old)), tokens(strip_sv(new))
        if a != b:
            k = first_diff(a, b)
            return "CHANGED", "token %d: base [%s] new [%s]" % (k, context(a, k), context(b, k))
        detail = "%d tokens" % len(a)
        pa = preprocess(old, defines, incdirs)
        if pa is not None:
            pb = preprocess(new, defines, incdirs)
            if pa.startswith("ERROR") or pb.startswith("ERROR"):
                if pa != pb:
                    return "CHANGED", "preprocessor: base %s / new %s" % (pa[:80], pb[:80])
                detail += ", preprocessor skipped (%s)" % pa[:60]
            else:
                ta, tb = tokens(strip_sv(pa)), tokens(strip_sv(pb))
                if ta != tb:
                    k = first_diff(ta, tb)
                    return "CHANGED", "preprocessed token %d: base [%s] new [%s]" % (
                        k, context(ta, k), context(tb, k))
                detail += ", %d preprocessed tokens" % len(ta)
        return "OK", detail
    if ext in TCL_EXT:
        a, b = tcl_lines(old), tcl_lines(new)
        if a != b:
            k = first_diff(a, b)
            la = a[k] if k < len(a) else "<end>"
            lb = b[k] if k < len(b) else "<end>"
            return "CHANGED", "command line %d: base [%s] new [%s]" % (k, la, lb)
        return "OK", "%d command lines" % len(a)
    return "UNCHECKED", "file type not checked"


def git(*args, cwd=None):
    return subprocess.run(["git"] + list(args), capture_output=True, text=True, cwd=cwd, check=True).stdout


def git_show(rev, path):
    r = subprocess.run(["git", "show", "%s:%s" % (rev, path)], capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", errors="surrogateescape")


def read_new(head, path):
    if head:
        return git_show(head, path)
    if not os.path.exists(path):
        return None
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8", errors="surrogateescape")


def self_test():
    vhd = 'a <= "--x" & \'-\'; -- note\nb <= c; -- synthesis translate_off\n'
    assert tokens(strip_vhdl(vhd)) == tokens(strip_vhdl(vhd.replace("note", "other note")))
    assert tokens(strip_vhdl(vhd)) != tokens(strip_vhdl(vhd.replace("translate_off", "translate_on")))
    assert tokens(strip_vhdl(vhd)) != tokens(strip_vhdl(vhd.replace("b <= c", "b <= d")))
    assert tokens(strip_vhdl("-- Synthesis-only top\n")) == tokens(strip_vhdl("-- Check top\n"))
    assert tokens(strip_vhdl(vhd)) != tokens(strip_vhdl(vhd.replace('"--x"', '"--y"')))
    sv = 'assign a = "//x"; // c\n/* block\n comment */ assign b = c; /* synthesis keep */\n'
    assert tokens(strip_sv(sv)) == tokens(strip_sv(sv.replace("block", "other block\n more")))
    assert tokens(strip_sv(sv)) != tokens(strip_sv(sv.replace("synthesis keep", "synthesis preserve")))
    assert tokens(strip_sv(sv)) != tokens(strip_sv(sv.replace("b = c", "b = d")))
    qsf = 'set_global_assignment -name SEED 8\n# comment\n'
    assert tcl_lines(qsf) == tcl_lines(qsf.replace("comment", "other"))
    assert tcl_lines(qsf) != tcl_lines(qsf.replace("SEED 8", "SEED 2"))
    if shutil.which("verilator"):
        d = "`define M(x) \\\n  (x + 1)\nmodule m; wire w = `M(2); endmodule\n"
        bad = d.replace("\\\n  (x", "\\\n// c\n  (x")
        st, _ = compare("t.sv", d, bad, [], [])
        assert st == "CHANGED", "comment inside a `define continuation not caught"
        st, _ = compare("t.sv", d, "// c\n" + d, [], [])
        assert st == "OK"
    print("self-test passed")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", help="base revision (required unless --self-test)")
    ap.add_argument("--head", help="second revision (default: working tree)")
    ap.add_argument("--qsf", help="take VERILOG_MACRO defines for the preprocessor pass from this .qsf")
    ap.add_argument("-I", dest="incdirs", action="append", default=[], help="include directory for the preprocessor")
    ap.add_argument("--allow-new", default="", help="comma list of extensions that may be added or deleted")
    ap.add_argument("--ignore", action="append", default=[], help="glob of paths to skip (repeatable)")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.base:
        ap.error("--base is required")

    top = git("rev-parse", "--show-toplevel").strip()
    os.chdir(top)
    defines = qsf_macros(args.qsf) if args.qsf else []
    incdirs = args.incdirs or [".", "rtl", "rtl/gnet", "sys"]
    allow_new = {e if e.startswith(".") else "." + e for e in args.allow_new.split(",") if e}

    if args.files:
        paths = args.files
    else:
        rng = [args.base, args.head] if args.head else [args.base]
        paths = [p for p in git("diff", "--name-only", *rng).splitlines() if p]
        if not args.head:
            paths += [p for p in git("ls-files", "--others", "--exclude-standard").splitlines() if p]

    fails = 0
    counts = {}
    for p in sorted(set(paths)):
        if any(fnmatch.fnmatch(p, g) for g in args.ignore):
            continue
        old = git_show(args.base, p)
        new = read_new(args.head, p)
        ext = os.path.splitext(p)[1].lower()
        if old is None or new is None:
            what = "ADDED" if old is None else "DELETED"
            if ext in allow_new:
                status, detail = "OK", what.lower() + " (allowed type)"
            else:
                status, detail = what, "not allowed"
        elif old == new:
            continue
        else:
            status, detail = compare(p, old, new, defines, incdirs)
        counts[status] = counts.get(status, 0) + 1
        if status != "OK":
            fails += 1
        print("%-9s %s: %s" % (status, p, detail))
    print("summary: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())) if counts else "summary: no differing files")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
