# Solomon's Survivor - agent rules (opencode reads this automatically; keep it short)

Godot 4.7 GDScript game in `survivor/`. The author tests in-engine (F5); you never do.

## Environment (do not rediscover)
- Shell is **Windows PowerShell 5.1**, not bash. There is no `tail head wc grep cat`, no `&&`, no heredocs. Chain with `;`.
  Trim output with `| Select-Object -First 30` / `-Last 30`.
- cwd = the git root. The Godot project is `./survivor`. Use **relative** paths (`survivor/tools/evo.py`). Never type an absolute path.
- `python` works (Python 3). Run scripts as `python survivor/tools/<name>.py`.

## Editing (the #1 source of wasted tokens)
- Change files ONLY with the Edit / Write tools. Never PowerShell `Set-Content / Out-File / -replace`, never `python -c`, never a
  script that rewrites source. They corrupt encoding and indentation.
- If an Edit fails twice on the same file: STOP and tell the author what failed. Do not invent a shell workaround.
- Indentation: copy the leading whitespace of the neighbouring lines exactly (some files use tabs, some 4 spaces, some CRLF).
  Keep each file's existing line endings; never mass-normalize them. Insert a whole block in ONE Edit.
- After every edited .gd file run `python survivor/tools/check_text.py` (1 second).
  TAB/SPACE/MIXED-EOL errors -> `python survivor/tools/check_text.py --fix`. OVER-INDENT / BAD-STEP -> re-edit that block once.
- Do not re-read a file you just edited successfully. Do not paste diffs or file contents back into chat.

## Reading (keep context small)
- Locate with Grep (specific pattern, e.g. `^class ChainLightning` or `has_evo\("capacitor"`), then Read with offset/limit (<= 150 lines).
  Never Read a whole file over 300 lines. Never use a one-word grep like `vel`.
- Do NOT read `survivor/workbench.md` in full. Grep for the section you need (`## 9.`).
- Design source of truth for evolutions: `survivor/tools/evo_data.py` (one `E(...)` row per option). Read only the rows you implement.

## Verify (cheapest first)
1. `python survivor/tools/check_text.py`                       after each edited file
2. `python survivor/tools/evo.py status <ability_id ...>`      shows exactly what is wired / missing; exits 1 until every row is `ok`
3. `python survivor/tools/evo.py check`                        all abilities, dangerous errors only (todo slices are ignored)
4. `powershell -NoProfile -ExecutionPolicy Bypass -File survivor/tools/check_all.ps1`   once, when a slice is finished
Never run `gen_data.py` (it rewrites every .tres and wipes hand edits). Never touch `Solomon's Survivor Demo/`.

## Evolution slice recipe (one ability pair, e.g. merlins_book + astral_projection)
1. Behavior: implement INLINE in `weapon_behaviors.gd` / `passive_behaviors.gd` with `has_evo("id")` and `evo_param("id", "key", default)`.
   No module class and no `make()` arm unless the option needs a hook (`on_kill`, `on_player_cast`, ...). No empty stub classes.
2. Register: add the id to `EvoRegistry.READY` in `src/abilities/evo/evo_registry.gd` (the ONLY ready-list).
3. Emit LAST: `python survivor/tools/evo.py emit <ability_id ...>`. Emitting makes the cards appear in game, so it comes after the code.
4. `python survivor/tools/evo.py status <ids>` must exit 0 with every row `ok` and no ERR lines.
5. `check_all.ps1`, then add ONE merged line to workbench section 9 (edit the existing line, do not append a paragraph).

## Todo discipline
- Keep one todo list. Mark each step done the moment it finishes, before starting the next. Take steps in order unless a
  dependency forces otherwise (say so in one line).
- Finish with <= 6 lines: files changed, check results, what is next. No recap of the code.
