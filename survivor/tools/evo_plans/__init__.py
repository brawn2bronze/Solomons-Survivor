"""Evolution plans for hand-maintained characters.

Add a character: create <character_id>.py with OPTIONS and CAPS, append the module
to PLAN_MODULES, then run `python tools/evo.py check` and `python tools/check_evo.py`.
"""
from . import fun_guy, jack

PLAN_MODULES = (jack, fun_guy)

PLAN_OPTIONS = [o for m in PLAN_MODULES for o in m.OPTIONS]

PLAN_CAPS = {}
for _module in PLAN_MODULES:
    for _aid, _caps in _module.CAPS.items():
        if _aid in PLAN_CAPS:
            raise ValueError("duplicate plan caps for " + _aid)
        PLAN_CAPS[_aid] = _caps

_ids = [o["id"] for o in PLAN_OPTIONS]
_dupes = sorted({i for i in _ids if _ids.count(i) > 1})
if _dupes:
    raise ValueError("duplicate plan option ids: " + ", ".join(_dupes))

PLAN_ABILITY_IDS = frozenset(o["ability"] for o in PLAN_OPTIONS)
