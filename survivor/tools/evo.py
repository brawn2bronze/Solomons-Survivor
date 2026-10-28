#!/usr/bin/env python3
"""evo.py - the whole evolution-slice workflow in three commands (design source: survivor/tools/evo_data.py).

  python survivor/tools/evo.py status [ability_id ...]   wiring matrix: what is done / missing, per option. No ids = all abilities in evo_data.
                                                        With explicit ids this exits 1 unless every row is fully wired.
  python survivor/tools/evo.py check                     all abilities, but only prints dangerous ERR rows; exits 1 if any exist.
                                                        Normal unimplemented `todo` slices are ignored.
  python survivor/tools/evo.py emit   <ability_id ...>   write evo1/evo2 tables into data/weapons|passives/<id>.tres (in place).
                                                        Touches ONLY the `branches = [...]` value. Never run gen_data.py for this:
                                                        it rewrites every .tres and wipes hand edits.
  add --dry to emit to preview without writing.

Per-option checks (status):
  tres   the option id is present in the ability's .tres table (= the card can be offered)
  ready  the id is in EvoRegistry.READY (the gate Ability._tier_ready reads)
  code   behavior exists: a real module class, or has_evo("id") / evo_param("id", ...) used in src/
ERR rows are dangerous: offered but dead (tres without code), emitted but invisible (tres without ready),
or registered ready while still dead (ready without code).
Footer also checks the string-dispatched things the GDScript parser cannot see:
  hook("name") calls / on_* overrides that evo_module.gd does not declare, and ab.call("name") targets that do not exist.
  It also reports ids in EvoRegistry.READY that are missing from evo_data.py.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import evo_data  # noqa: E402  (authored options + CAPS; the design source of truth)


def rd(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def tres_path(aid):
    for d in ("weapons", "passives"):
        p = os.path.join(ROOT, "data", d, aid + ".tres")
        if os.path.isfile(p):
            return p
    return None


# ------------------------------------------------------------------------------------------ .tres span helpers
def find_branches_span(text):
    """(start, end) of the `[...]` value after a line starting `branches = `, string-aware. None if absent."""
    m = re.search(r"(?m)^branches = ", text)
    if not m:
        return None
    i = text.find("[", m.end())
    if i < 0:
        return None
    depth, j, in_str = 0, i, False
    while j < len(text):
        ch = text[j]
        if in_str:
            if ch == "\\":
                j += 1
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return i, j + 1
        j += 1
    return None


# ------------------------------------------------------------------------------------------------------- emit
def cmd_emit(ids, dry):
    if not ids:
        print("evo emit: give at least one ability id (e.g. merlins_book astral_projection)")
        return 2
    rc = 0
    for aid in ids:
        opts = [o for o in evo_data.OPTIONS if o["ability"] == aid]
        if not opts:
            print(f"evo emit: {aid}: no options in evo_data.py")
            rc = 1
            continue
        path = tres_path(aid)
        if path is None:
            print(f"evo emit: {aid}: no data/weapons|passives/{aid}.tres")
            rc = 1
            continue
        text = rd(path)
        span = find_branches_span(text)
        if span is None:
            print(f"evo emit: {aid}: could not find `branches = [...]` in {os.path.relpath(path, ROOT)}")
            rc = 1
            continue
        try:
            branches = json.loads(text[span[0]:span[1]])
        except ValueError as exc:
            print(f"evo emit: {aid}: branches value is not plain JSON-compatible ({exc}); file left untouched")
            rc = 1
            continue
        if not isinstance(branches, list) or len(branches) != 2:
            print(f"evo emit: {aid}: expected exactly 2 branches, found {len(branches) if isinstance(branches, list) else '?'}; untouched")
            rc = 1
            continue
        slots = {}
        for o in opts:
            slots.setdefault((o["branch"], o["tier"]), []).append(o)
        bad = [k for k, v in slots.items() if len(v) != 2]
        if bad:
            print(f"evo emit: {aid}: every (branch, tier) needs exactly 2 options, bad slots: {bad}; untouched")
            rc = 1
            continue
        for (br, tier), group in sorted(slots.items()):
            branches[0 if br == "a" else 1]["evo1" if tier == 1 else "evo2"] = [evo_data._option_dict(o) for o in group]
        new_text = text[:span[0]] + json.dumps(branches, ensure_ascii=False) + text[span[1]:]
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if new_text == text:
            print(f"evo emit: {aid}: already up to date ({rel})")
            continue
        if dry:
            print(f"evo emit: {aid}: WOULD update {rel} ({len(slots)} slots, {len(opts)} options)")
            continue
        with open(path, "wb") as f:
            f.write(new_text.encode("utf-8"))
        print(f"evo emit: {aid}: updated {rel} ({len(slots)} slots, {len(opts)} options)")
    if rc == 0 and not dry:
        print("evo emit: next -> python survivor/tools/evo.py status " + " ".join(ids))
    return rc


# ----------------------------------------------------------------------------------------------------- status
def src_files():
    out = []
    for p in glob.glob(os.path.join(ROOT, "src", "**", "*.gd"), recursive=True):
        out.append(p)
    return out


def module_classes():
    """{ 'WizardEvo.StaticCharge': (is_real, {ab.call targets}) } for every inner class that extends EvoModule."""
    res = {}
    for p in glob.glob(os.path.join(ROOT, "src", "abilities", "evo", "*.gd")):
        t = rd(p)
        m = re.search(r"(?m)^class_name (\w+)", t)
        outer = m.group(1) if m else None
        if not outer:
            continue
        for cm in re.finditer(r"(?m)^class (\w+) extends EvoModule:\s*\n((?:[ \t]+.*\n|\s*\n)*)", t + "\n"):
            body = cm.group(2)
            code = [ln.strip() for ln in body.split("\n") if ln.strip() and not ln.strip().startswith("#") and not ln.strip().startswith("##")]
            real = any(ln.startswith("func ") for ln in code)
            calls = set(re.findall(r'\bab\.call\(\s*"(\w+)"', body))
            res[f"{outer}.{cm.group(1)}"] = (real, calls)
    return res


def cmd_status(ids, errors_only=False):
    abilities = []
    for o in evo_data.OPTIONS:
        if o["ability"] not in abilities:
            abilities.append(o["ability"])
    if ids:
        unknown = [i for i in ids if i not in abilities]
        if unknown:
            print("evo status: not in evo_data.py: " + ", ".join(unknown))
            return 2
        abilities = ids

    all_ids = {o["id"] for o in evo_data.OPTIONS}
    reg_path = os.path.join(ROOT, "src", "abilities", "evo", "evo_registry.gd")
    reg = rd(reg_path) if os.path.isfile(reg_path) else ""
    ready_block = reg.split("static func is_ready")[0]
    ready = set(re.findall(r'"(\w+)"\s*:\s*true', ready_block))
    orphan_ready = sorted(ready - all_ids)
    arms = dict(re.findall(r'"(\w+)"\s*:\s*return (\w+\.\w+)\.new\(\)', reg))
    classes = module_classes()
    srcs = {p: rd(p) for p in src_files()}
    behavior_txt = "\n".join(t for p, t in srcs.items() if not p.endswith("evo_registry.gd"))

    behaviors = "\n".join(srcs[p] for p in srcs if p.endswith(("weapon_behaviors.gd", "passive_behaviors.gd", "ability.gd")))

    def func_exists(name):
        return bool(re.search(r"(?m)^\s*func %s\(" % re.escape(name), behaviors))

    err = 0
    not_ok = 0
    for aid in abilities:
        tp = tres_path(aid)
        ttxt = rd(tp) if tp else ""
        rows = [o for o in evo_data.OPTIONS if o["ability"] == aid]
        if not errors_only:
            print(f"\n{aid}  ({os.path.relpath(tp, ROOT).replace(chr(92), '/') if tp else 'NO .tres'})")
            print("  %-20s %-3s %-4s %-6s %-5s %s" % ("option", "br", "tier", "tres", "ready", "code"))
        ok_n = 0
        for o in rows:
            oid = o["id"]
            in_tres = bool(re.search(r'"id"\s*:\s*"%s"' % re.escape(oid), ttxt))
            in_ready = oid in ready
            cls = arms.get(oid)
            module = ""
            real = False
            dead_calls = []
            if cls:
                if cls in classes:
                    real, calls = classes[cls]
                    module = "module" if real else "stub"
                    dead_calls = sorted(c for c in calls if not func_exists(c))
                    if dead_calls:
                        real = False
                        module = "module(needs " + ",".join(dead_calls) + ")"
                else:
                    module = "MISSING-CLASS " + cls
            inline = bool(re.search(r'(?:has_evo|evo_param)\(\s*"%s"' % re.escape(oid), behavior_txt))
            has_code = real or inline
            code = ("inline" if inline else "") + (" " if inline and module else "") + module
            if module.startswith("MISSING"):
                has_code = False
            status = "ok"
            if in_tres and not has_code:
                status = "ERR offered-but-dead"
            elif in_tres and not in_ready:
                status = "ERR emitted-but-invisible"
            elif in_ready and not has_code:
                status = "ERR ready-but-dead"
            elif in_ready and not in_tres and has_code:
                status = "todo: emit"
            elif not has_code:
                status = "todo: code"
            elif not in_ready:
                status = "todo: ready"
            if status == "ok":
                ok_n += 1
            else:
                not_ok += 1
            if status.startswith("ERR"):
                err += 1
                if errors_only:
                    print(f"ERR {aid}/{oid}: {status} ({code or '-'})")
            if not errors_only:
                print("  %-20s %-3s %-4s %-6s %-5s %-36s %s" % (oid, o["branch"], o["tier"], "Y" if in_tres else "-", "Y" if in_ready else "-", code or "-", status if status != "ok" else ""))
        if not errors_only:
            print(f"  => {ok_n}/{len(rows)} fully wired")

    # ---- string-dispatched things the parser cannot check -------------------------------------------------
    base_path = os.path.join(ROOT, "src", "abilities", "evo", "evo_module.gd")
    base = rd(base_path) if os.path.isfile(base_path) else ""
    declared = set(re.findall(r"(?m)^func (\w+)\(", base))
    used_hooks = set(re.findall(r'\bhook\(\s*"(\w+)"', behavior_txt))
    overridden = set()
    for p in glob.glob(os.path.join(ROOT, "src", "abilities", "evo", "*_evo.gd")):
        overridden |= set(re.findall(r"(?m)^\s+func (on_\w+)\(", rd(p)))
    need = sorted((used_hooks | overridden) - declared)
    if not base:
        if errors_only:
            print("ERR hooks: evo_module.gd not found")
            err += 1
        else:
            print("\nhooks: evo_module.gd not found - skipped")
    elif need:
        print("ERR hooks not declared in evo_module.gd (modules would crash on m.call): " + ", ".join(need))
        err += 1
    elif not errors_only:
        print("\nhooks: OK (every hook name used or overridden is declared in evo_module.gd)")

    missing_calls = []
    for p in glob.glob(os.path.join(ROOT, "src", "abilities", "evo", "*_evo.gd")):
        for name in sorted(set(re.findall(r'\bab\.call\(\s*"(\w+)"', rd(p)))):
            if not func_exists(name):
                missing_calls.append(f"{name} (called from {os.path.basename(p)})")
    if missing_calls:
        print("ERR ab.call targets with no func yet: " + "; ".join(missing_calls))
        err += 1
    elif not errors_only:
        print("calls: OK (every ab.call(\"name\") in evo modules has a func)")

    if orphan_ready:
        print("ERR ready ids missing from evo_data.py: " + ", ".join(orphan_ready))
        err += 1
    elif not errors_only:
        print("ready: OK (every EvoRegistry.READY id exists in evo_data.py)")

    if errors_only:
        if err:
            print(f"evo check: {err} dangerous error(s)")
        else:
            print("evo check: OK (no dangerous wiring errors; todo slices ignored)")
        return 1 if err else 0

    return 1 if (err or (ids and not_ok)) else 0


def main(argv):
    if not argv or argv[0] not in ("status", "emit", "check"):
        print(__doc__)
        return 2
    rest = [a for a in argv[1:] if not a.startswith("--")]
    if argv[0] == "emit":
        return cmd_emit(rest, "--dry" in argv)
    if argv[0] == "check":
        return cmd_status([], errors_only=True)
    return cmd_status(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
