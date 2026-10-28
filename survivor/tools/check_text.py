#!/usr/bin/env python3
"""check_text.py - whitespace/encoding guard for the Godot project (replaces the hand-kept lists in check_text.ps1).

No per-file lists to maintain. The expected indent style of a file is whatever it has at git HEAD.
Line endings are not compared to HEAD (core.autocrlf makes that unreliable); each file only has to be
internally consistent. A new (untracked) file only has to be internally consistent too.

  python survivor/tools/check_text.py             check every .gd file (about 1 second)
  python survivor/tools/check_text.py --fix       also repair leading-whitespace + mixed line endings in place
  python survivor/tools/check_text.py --classify  print the detected style of every file
  python survivor/tools/check_text.py --max 40    show more than the default 15 violations

Catches: mojibake, tab/space mixing, a whole-file style flip vs HEAD, odd indent widths, mixed line endings,
and a body line indented deeper than its parent (no block opener, or more than one level in) - the 'Could not parse global class' bug.
Exit code 1 when anything is left unfixed. --fix never touches anything except leading whitespace and line endings.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # the Godot project folder (.../survivor)
SKIP_DIRS = {".git", ".godot", "__pycache__", "node_modules"}
MOJIBAKE = ["\u00e2\u20ac", "\u00c2\u00a7", "\u00c3\u00a9", "\u00e2\u201e", "\u00e2\u2019"]


def git_head(rel):
    """Bytes of the file at HEAD, or None (untracked / no git)."""
    try:
        r = subprocess.run(["git", "-C", ROOT, "show", "HEAD:./" + rel], capture_output=True, timeout=30)
    except Exception:
        return None
    return r.stdout if r.returncode == 0 else None


def split_lines(text):
    """Lines WITHOUT their line ending, plus the endings list (so --fix can rebuild exactly)."""
    parts = re.split(r"(?<=\n)", text)
    if parts and parts[-1] == "":
        parts.pop()
    bodies, ends = [], []
    for p in parts:
        if p.endswith("\r\n"):
            bodies.append(p[:-2]); ends.append("\r\n")
        elif p.endswith("\n"):
            bodies.append(p[:-1]); ends.append("\n")
        else:
            bodies.append(p); ends.append("")
    return bodies, ends


def code_mask(bodies):
    """True for lines that are code (False inside triple-quoted blocks, incl. the opening/closing line)."""
    mask, in_str = [], False
    for line in bodies:
        q = line.count('"""')
        if in_str:
            mask.append(False)
            if q % 2 == 1:
                in_str = False
            continue
        if q % 2 == 1:
            in_str = True
            mask.append(False)
            continue
        mask.append(True)
    return mask


def lead_of(line):
    i = 0
    while i < len(line) and line[i] in "\t ":
        i += 1
    return line[:i]


def detect_style(bodies, mask):
    t = s = 0
    for line, is_code in zip(bodies, mask):
        if not is_code or not line:
            continue
        if line[0] == "\t":
            t += 1
        elif line[0] == " ":
            s += 1
    if t and s:
        return "TAB" if t >= s * 4 else ("SPACE" if s >= t * 4 else "MIXED"), t, s
    if t:
        return "TAB", t, s
    if s:
        return "SPACE", t, s
    return "FLAT", t, s


def detect_eol(data):
    crlf = data.count(b"\r\n")
    lf = data.count(b"\n") - crlf
    if crlf == 0 and lf == 0:
        return "NONE", crlf, lf
    return ("CRLF" if crlf > lf else "LF"), crlf, lf


def decode(data):
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def check_file(rel, data, head_data):
    """-> (violations[list of str], info dict)."""
    v = []
    text = decode(data)
    if text is None:
        return [f"NOT-UTF8 {rel}"], {}
    bodies, ends = split_lines(text)
    mask = code_mask(bodies)
    style, nt, ns = detect_style(bodies, mask)
    eol, ncrlf, nlf = detect_eol(data)
    info = {"style": style, "t": nt, "s": ns, "eol": eol}

    for pat in MOJIBAKE:
        idx = text.find(pat)
        if idx >= 0:
            v.append(f"MOJIBAKE {rel}:{text.count(chr(10), 0, idx) + 1} (CP1252 round-trip)")
            break

    # ---- expected style --------------------------------------------------------------------------------------
    exp = None
    if head_data is not None:
        htext = decode(head_data)
        if htext is not None:
            hb, _ = split_lines(htext)
            hs, _, _ = detect_style(hb, code_mask(hb))
            if hs in ("TAB", "SPACE"):
                exp = hs
            elif hs == "FLAT" and rel.startswith("data/defs/"):
                exp = "FLAT"
    if exp is None:
        exp = style if style in ("TAB", "SPACE") else ("FLAT" if rel.startswith("data/defs/") else None)
    if exp is None and style == "MIXED":
        exp = "SPACE"          # no reference: report the minority style
    info["expect"] = exp
    if exp in ("TAB", "SPACE") and style in ("TAB", "SPACE") and style != exp:
        v.append(f"STYLE-FLIP {rel} (HEAD={exp}, now={style}) - run --fix")
    if ncrlf and nlf:
        v.append(f"MIXED-EOL {rel} ({ncrlf} CRLF, {nlf} LF) - run --fix")

    # ---- per-line checks -------------------------------------------------------------------------------------
    for n, (line, is_code) in enumerate(zip(bodies, mask), 1):
        if not is_code or not line:
            continue
        lead = lead_of(line)
        if not lead:
            continue
        has_tab = "\t" in lead
        has_sp = " " in lead
        if has_tab and has_sp:
            v.append(f"MIXED-WS {rel}:{n}")
            continue
        if exp == "TAB" and has_sp:
            v.append(f"SPACE-IN-TAB {rel}:{n}")
        if exp == "SPACE" and has_tab:
            v.append(f"TAB-IN-SPACE {rel}:{n}")
        if exp == "SPACE" and has_sp and len(lead) % 4 != 0:
            v.append(f"ODD-INDENT {rel}:{n} ({len(lead)} spaces)")
        if exp == "FLAT":
            v.append(f"INDENT-IN-FLAT {rel}:{n}")

    # ---- depth sanity: body deeper than its parent with no block opener and no open bracket --------------
    prev_depth, prev_opens, brace = -1, True, 0
    for n, (line, is_code) in enumerate(zip(bodies, mask), 1):
        if not is_code:
            continue
        trim = line.strip()
        if not trim or trim.startswith("#"):
            continue
        lead = lead_of(line)
        depth = len(lead.replace("\t", "    ")) // 4
        code = re.sub(r"'[^']*'", "''", re.sub(r'"[^"]*"', '""', trim)).split("#")[0].rstrip()
        opens = code.endswith(":")
        if depth > prev_depth and not prev_opens and brace <= 0:
            v.append(f"OVER-INDENT {rel}:{n} (depth {depth} after depth {prev_depth})")
        elif prev_opens and prev_depth >= 0 and depth > prev_depth + 1 and brace <= 0:
            v.append(f"BAD-STEP {rel}:{n} (block body is depth {depth}, its opener is depth {prev_depth})")
        for ch in code:
            if ch in "([{":
                brace += 1
            elif ch in ")]}":
                brace -= 1
        if brace < 0:
            brace = 0
        prev_depth, prev_opens = depth, opens
    return v, info


def fix_file(rel, path, data, exp):
    """Rewrite ONLY leading whitespace of code lines and mixed line endings. Returns number of lines changed (0 = untouched)."""
    text = decode(data)
    if text is None or exp not in ("TAB", "SPACE"):
        return 0
    bodies, ends = split_lines(text)
    mask = code_mask(bodies)
    changed = 0
    for i, (line, is_code) in enumerate(zip(bodies, mask)):
        if not is_code or not line:
            continue
        lead = lead_of(line)
        if not lead:
            continue
        cols = len(lead.replace("\t", "    "))
        if exp == "SPACE":
            new = " " * cols
        else:
            new = "\t" * (cols // 4) + " " * (cols % 4)
        if new != lead:
            bodies[i] = new + line[len(lead):]
            changed += 1
    eol, _, _ = detect_eol(data)
    target = eol if eol in ("CRLF", "LF") else "LF"
    eol_str = "\r\n" if target == "CRLF" else "\n"
    out = []
    eol_changed = 0
    for body, end in zip(bodies, ends):
        want = eol_str if end else ""
        if end and end != want:
            eol_changed += 1
        out.append(body + want)
    if not changed and not eol_changed:
        return 0
    with open(path, "wb") as f:
        f.write("".join(out).encode("utf-8"))
    return changed + eol_changed


def gather():
    files = []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP_DIRS and not d.startswith(".")]
        for f in fn:
            if f.endswith(".gd"):
                full = os.path.join(dp, f)
                files.append((os.path.relpath(full, ROOT).replace("\\", "/"), full))
    files.sort()
    return files


def main(argv):
    flags = {a.lower().lstrip("-") for a in argv if a.startswith("-")}
    max_show = 15
    if "--max" in argv:
        try:
            max_show = int(argv[argv.index("--max") + 1])
        except Exception:
            pass
    files = gather()
    all_v = []
    fixed = []
    for rel, full in files:
        with open(full, "rb") as fh:
            data = fh.read()
        head = git_head(rel)
        v, info = check_file(rel, data, head)
        if "classify" in flags:
            print("%s\t%s\t(t=%s s=%s eol=%s)" % (info.get("style", "?"), rel, info.get("t"), info.get("s"), info.get("eol")))
            continue
        if v and "fix" in flags and info:
            n = fix_file(rel, full, data, info.get("expect"))
            if n:
                fixed.append((rel, n))
                with open(full, "rb") as fh:
                    data = fh.read()
                v, info = check_file(rel, data, head)
        all_v.extend(v)
    if "classify" in flags:
        return 0
    for rel, n in fixed:
        print(f"check_text: fixed {n} line(s) in {rel}")
    uniq = sorted(set(all_v))
    if not uniq:
        print(f"check_text: OK ({len(files)} .gd files clean)")
        return 0
    print(f"check_text: {len(uniq)} violation(s)")
    for line in uniq[:max_show]:
        print("  " + line)
    if len(uniq) > max_show:
        print(f"  ... and {len(uniq) - max_show} more (use --max {len(uniq)})")
    if any(u.split(" ")[0] in ("OVER-INDENT", "ODD-INDENT", "BAD-STEP") for u in uniq):
        print("  hint: OVER-INDENT / ODD-INDENT / BAD-STEP need a human fix - re-edit that block copying the indentation of the line above it.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
