#!/usr/bin/env python3
"""GDScript lint for Solomon's Survivor - the single owner of the two rules that
mirror Godot's own diagnostics:

    R1  INFERRED_DECLARATION   `var x := <Variant expression>`   -> Godot: Parse Error
    R2  UNUSED_PARAMETER       a parameter that is never used      -> Godot: Warning

R1 replaces the regex heuristic that used to live in check_project.py.  It keeps that
heuristic's direct triggers and adds taint tracking, so a value that came out of a
Variant source is followed through assignments:

    var e := ctx.get("e")      # ctx.get() returns Variant
    var marks := e.marks       # <- caught: e is Variant, so e.marks is Variant

Only *definitely* Variant expressions are reported.  Anything the linter cannot
resolve (an unknown member type, an engine method it does not know) is treated as
fine: precision over recall, because a check that cries wolf gets ignored.

The rule was calibrated against Godot 4.7.2 headless (see tools/check_parse.ps1):
on this project it reports exactly the errors the engine reports and nothing else.

Severity
    direct  the expression itself produces a Variant (Dictionary.get(), a subscript of
            an untyped container, an untyped parameter, an untyped function's return).
            These are hard engine errors -> reported as ERROR.
    chained the expression is only Variant because a variable it uses was assigned
            from a Variant. Also a hard engine error, but this is the NEW part of the
            rule, so it is a REVIEW item until PROMOTE_NEW_LINT_RULES is flipped.
    R2 is always a REVIEW item (Godot's own unused_parameter warning).

Usage
    python tools/gdscript_lint.py                # lint the whole project
    python tools/gdscript_lint.py --promote      # chained findings count as errors
    python tools/gdscript_lint.py src/ui/hud.gd  # lint one file
"""
import glob
import os
import re
import sys

# Flip to True to promote the chained (taint-propagated) findings from REVIEW to
# ERROR. Left False on purpose: the rule was calibrated against the engine and is
# clean, but the author reviews the first run before the gate hardens.
PROMOTE_NEW_LINT_RULES = False

KNOWN, VARIANT, UNKNOWN = "known", "variant", "unknown"


class Ty:
    """A resolved type: kind + how it became Variant + the type name when known."""
    __slots__ = ("kind", "direct", "name", "why", "source")

    def __init__(self, kind, direct=False, name=None, why="", source=None):
        self.kind = kind
        self.direct = direct
        self.name = name
        self.why = why
        self.source = source

    @property
    def is_variant(self):
        return self.kind == VARIANT

    def __repr__(self):
        return "Ty(%s,direct=%s,name=%s,why=%s)" % (self.kind, self.direct, self.name, self.why)


T_KNOWN = Ty(KNOWN)
T_UNKNOWN = Ty(UNKNOWN)


def t_var(direct, why):
    return Ty(VARIANT, direct, None, why)


class Finding:
    __slots__ = ("path", "line", "severity", "code", "message")

    def __init__(self, path, line, severity, code, message):
        self.path = path          # path relative to the project root, forward slashes
        self.line = line
        self.severity = severity  # "error" | "review"
        self.code = code
        self.message = message

    def __str__(self):
        return "%s:%d: %s: %s" % (self.path, self.line, self.severity.upper(), self.message)


# --------------------------------------------------------------------------------------
# Built-in conversions: a call to one of these always yields a known type, which is what
# makes `float(ctx.get("amount", 0.0))` legal while `var x := ctx.get("amount")` is not.
# --------------------------------------------------------------------------------------
CAST_FUNCS = {
    "float", "int", "bool", "str", "String", "Vector2", "Vector2i", "Rect2", "Rect2i",
    "Color", "Point2", "Plane", "Quaternion", "AABB", "Transform2D", "Transform3D",
    "NodePath", "Callable", "Signal", "RID", "Object", "PackedVector2Array",
    "PackedVector3Array", "PackedFloat32Array", "PackedFloat64Array", "PackedInt32Array",
    "PackedInt64Array", "PackedStringArray", "PackedColorArray", "PackedByteArray",
    "abs", "absf", "absi", "ceil", "ceili", "ceilf", "clamp", "clampf", "clampi",
    "cos", "cosh", "deg_to_rad", "ease", "floor", "floori", "floorf", "fmod", "fposmod",
    "hash", "inverse_lerp", "is_equal_approx", "is_zero_approx", "lerp", "lerp_angle",
    "lerpf", "log", "max", "maxf", "maxi", "min", "minf", "mini", "move_toward",
    "nearest_po2", "pingpong", "posmod", "pow", "rad_to_deg", "rand_from_seed",
    "randf", "randf_range", "randfn", "randi", "randi_range", "remap", "round",
    "roundi", "roundf", "seed", "sign", "signf", "signi", "sin", "sinh", "snapped",
    "snappedf", "snappedi", "smoothstep", "sqrt", "step_decimals", "tan", "tanh",
    "type_convert", "var_to_str", "wrap", "wrapf", "wrapi",
}
# Engine methods whose result type is known without looking at the receiver.
SIMPLE_METHODS = {
    "size": "int", "length": "int", "count": "int", "hash": "int", "get_instance_id": "int",
    "has": "bool", "is_empty": "bool", "is_zero_approx": "bool", "is_equal_approx": "bool",
    "keys": "Array", "values": "Array", "duplicate": "Array", "get_slice": "PackedStringArray",
    "get_meta": "Variant", "to_string": "String", "str": "String", "get_path": "NodePath",
}


# --------------------------------------------------------------------------------------
# Project index: what every function in the project returns, which class each file is,
# which names are autoloads.
# --------------------------------------------------------------------------------------
class ProjectIndex:
    def __init__(self, root):
        self.root = root
        self.func_returns = {}   # name -> set of return types (None == untyped)
        self.class_files = {}     # class_name -> file path
        self.class_funcs = {}     # class_name -> {func name -> set of return types}
        self.autoloads = set()
        self._scan()

    def _scan(self):
        for path in gd_files(self.root):
            try:
                text = open(path, encoding="utf-8").read()
            except OSError:
                continue
            lines = text.split("\n")
            code = strip_literals(lines)
            cls = None
            m = re.search(r"^\s*class_name\s+([A-Za-z_]\w*)", "\n".join(code), re.M)
            if m:
                cls = m.group(1)
                self.class_files[cls] = path
            for lineno, line in enumerate(code, 1):
                sig = parse_func(line)
                if not sig:
                    continue
                name, params, ret = sig
                self.func_returns.setdefault(name, set()).add(ret)
                if cls:
                    self.class_funcs.setdefault(cls, {}).setdefault(name, set()).add(ret)
        self._scan_autoloads()

    def _scan_autoloads(self):
        pg = os.path.join(self.root, "project.godot")
        if not os.path.exists(pg):
            return
        try:
            text = open(pg, encoding="utf-8").read()
        except OSError:
            return
        m = re.search(r"^\[autoload\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
        if not m:
            return
        for line in m.group(1).split("\n"):
            mm = re.match(r"^\s*([A-Za-z_]\w*)\s*=", line)
            if mm:
                self.autoloads.add(mm.group(1))

    def resolve_func(self, name):
        """Return type of a call to `name()`, as a Ty."""
        rets = self.func_returns.get(name)
        if not rets:
            return T_UNKNOWN
        typed = {r for r in rets if r}
        if len(typed) == len(rets) and len(typed) == 1:
            return Ty(KNOWN, name=next(iter(typed)))
        if not typed:
            return t_var(True, "%s() has no return type" % name)
        if len(typed) == 1:
            return Ty(KNOWN, name=next(iter(typed)))
        return T_UNKNOWN

    def resolve_method(self, base_ty, name):
        """Return type of `base.name()`, as a Ty."""
        if base_ty.kind == VARIANT:
            return Ty(VARIANT, base_ty.direct, why=base_ty.why)
        if base_ty.kind == KNOWN and base_ty.name in self.class_files:
            rets = self.class_funcs.get(base_ty.name, {}).get(name)
            if rets:
                typed = {r for r in rets if r}
                if len(typed) == len(rets) == 1:
                    return Ty(KNOWN, name=next(iter(typed)))
                if not typed:
                    return t_var(True, "%s.%s() has no return type" % (base_ty.name, name))
                if len(typed) == 1:
                    return Ty(KNOWN, name=next(iter(typed)))
        return self.resolve_func(name)


# --------------------------------------------------------------------------------------
# Lexing helpers
# --------------------------------------------------------------------------------------
TOKEN_RE = re.compile(r"""
      (?P<ws>\s+)
    | (?P<num>\d+\.\d*|\.\d+|\d+)
    | (?P<str>"(?:\\.|[^"\\])*")
    | (?P<ident>[A-Za-z_]\w*)
    | (?P<op>->|:=|==|!=|<=|>=|\*\*|\+=|-=|\*=|/=|%=|\|\||&&|<<|>>|as|is|[-+*/%<>=!?:,.()\[\]{}@&|^~])
""", re.X)


def tokenize(text):
    out = []
    for m in TOKEN_RE.finditer(text):
        kind = m.lastgroup
        if kind == "ws":
            continue
        out.append((kind, m.group()))
    return out


def strip_literals(lines):
    """Blank out string literals and comments, keeping one output line per input line."""
    out = []
    in_triple = False
    for raw in lines:
        buf = []
        i = 0
        n = len(raw)
        if in_triple:
            idx = raw.find('"""')
            if idx < 0:
                out.append("")
                continue
            i = idx + 3
            in_triple = False
        while i < n:
            ch = raw[i]
            if ch == '"':
                if raw.startswith('"""', i):
                    j = raw.find('"""', i + 3)
                    if j < 0:
                        in_triple = True
                        i = n
                        break
                    i = j + 3
                    buf.append(" ")
                    continue
                j = i + 1
                while j < n:
                    if raw[j] == "\\":
                        j += 2
                        continue
                    if raw[j] == '"':
                        break
                    j += 1
                i = min(j + 1, n)
                buf.append('""')
                continue
            if ch == "#":
                break
            buf.append(ch)
            i += 1
        out.append("".join(buf))
    return out


def indent_level(code):
    lead = code[:len(code) - len(code.lstrip())]
    if "\t" in lead:
        return lead.count("\t")
    return len(lead) // 4


def split_params(text):
    """Split a parameter list on top-level commas."""
    out = []
    depth = 0
    cur = []
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    if "".join(cur).strip():
        out.append("".join(cur))
    return out


def parse_func(line):
    """-> (name, [(param_name, type_or_None)], return_type_or_None) or None."""
    m = re.match(r"^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(", line)
    if not m:
        return None
    name = m.group(1)
    i = m.end() - 1
    depth = 0
    end = None
    while i < len(line):
        if line[i] == "(":
            depth += 1
        elif line[i] == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    if end is None:
        return None
    params = []
    for raw in split_params(line[m.end():end]):
        raw = raw.strip()
        if not raw:
            continue
        pm = re.match(r"^([A-Za-z_]\w*)\s*(?::\s*([^=]+?))?\s*(?:=.*)?$", raw)
        if not pm:
            continue
        pname = pm.group(1)
        ptype = pm.group(2).strip() if pm.group(2) else None
        params.append((pname, ptype))
    tail = line[end + 1:]
    rm = re.search(r"->\s*([A-Za-z_][\w.\[\], ]*?)\s*:", tail)
    ret = rm.group(1).strip() if rm else None
    return name, params, ret


# --------------------------------------------------------------------------------------
# Expression typing
# --------------------------------------------------------------------------------------
def combine(left, right, op=None):
    if op == "%" and left.kind == KNOWN and left.name == "String":
        return Ty(KNOWN, name="String")
    if left.kind == VARIANT:
        return left
    if right.kind == VARIANT:
        return right
    if left.kind == KNOWN and right.kind == KNOWN:
        return Ty(KNOWN, name=left.name or right.name)
    return T_UNKNOWN


class ExprParser:
    """A small recursive-descent parser that answers one question per expression:
    is this value definitely Variant, and if so why?"""

    def __init__(self, tokens, scope, index):
        self.tokens = tokens
        self.i = 0
        self.scope = scope
        self.index = index

    # -- token helpers ---------------------------------------------------------------
    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def take(self):
        tok = self.peek()
        if tok is not None:
            self.i += 1
        return tok

    def accept(self, text):
        tok = self.peek()
        if tok is not None and tok[1] == text:
            self.i += 1
            return True
        return False

    def skip_balanced(self, open_ch, close_ch):
        depth = 0
        while True:
            tok = self.take()
            if tok is None:
                return
            if tok[1] == open_ch:
                depth += 1
            elif tok[1] == close_ch:
                depth -= 1
                if depth <= 0:
                    return

    # -- grammar ----------------------------------------------------------------------
    def parse(self):
        return self.parse_expr()

    def parse_expr(self):
        left = self.parse_bin()
        if self.accept("if"):
            cond = self.parse_bin()
            self.accept("else")
            right = self.parse_bin()
            return combine(left, right)
        return left

    def parse_bin(self):
        left = self.parse_postfix()
        while True:
            tok = self.peek()
            if tok is None:
                break
            # `as` and `is` are keywords, not operators, so the tokenizer keeps them
            # as identifiers - handle them here.
            if tok[0] == "ident" and tok[1] in ("as", "is"):
                self.take()
                if tok[1] == "as":
                    ty = self.take()
                    left = Ty(KNOWN, name=ty[1] if ty else None)
                else:
                    self.take()
                    left = T_KNOWN
                continue
            if tok[0] != "op":
                break
            op = tok[1]
            if op in ("=", ":=", "->", ":", ",", ".", ")", "]", "}", "?"):
                break
            self.take()
            right = self.parse_postfix()
            left = combine(left, right, op)
        return left

    def parse_postfix(self):
        base = self.parse_primary()
        while True:
            tok = self.peek()
            if tok is None:
                break
            if tok[1] == ".":
                self.take()
                name_tok = self.take()
                if name_tok is None:
                    break
                name = name_tok[1]
                if self.peek() is not None and self.peek()[1] == "(":
                    self.take()
                    self.skip_balanced("(", ")")
                    base = self.method_ty(base, name)
                else:
                    base = self.member_ty(base, name)
            elif tok[1] == "[":
                self.take()
                self.parse_expr()
                self.accept("]")
                base = self.subscript_ty(base)
            else:
                break
        return base

    def parse_primary(self):
        tok = self.take()
        if tok is None:
            return T_UNKNOWN
        kind, text = tok
        if kind == "num":
            return Ty(KNOWN, name="float" if "." in text else "int")
        if kind == "str":
            return Ty(KNOWN, name="String")
        if kind == "op":
            if text == "(":
                inner = self.parse_expr()
                self.accept(")")
                return inner
            if text == "[":
                self.skip_balanced("[", "]")
                return Ty(KNOWN, name="Array")
            if text == "{":
                self.skip_balanced("{", "}")
                return Ty(KNOWN, name="Dictionary")
            return T_UNKNOWN
        # identifier
        if text in ("true", "false", "null"):
            return T_KNOWN
        if text == "func":                       # lambda
            return Ty(KNOWN, name="Callable")
        nxt = self.peek()
        if nxt is not None and nxt[1] == "(":
            return self.call_ty(text)
        return self.lookup_var(text)

    # -- typing rules ----------------------------------------------------------------
    def call_ty(self, name):
        if name in CAST_FUNCS:
            self.skip_balanced("(", ")")
            return Ty(KNOWN, name=name)
        if name in ("load", "preload"):
            self.skip_balanced("(", ")")
            return Ty(KNOWN, name="Resource")
        self.skip_balanced("(", ")")
        return self.index.resolve_func(name)

    def lookup_var(self, name):
        ty = self.scope.lookup(name)
        if ty is not None:
            return ty
        if name == "self":
            return T_KNOWN
        if name in self.index.autoloads or name in self.index.class_files:
            return T_KNOWN
        return T_UNKNOWN

    def member_ty(self, base, name):
        if base.kind == VARIANT:
            return Ty(VARIANT, base.direct, why=base.why, source=base.source)
        if base.kind == KNOWN and base.name in ("Dictionary", "Array"):
            return T_UNKNOWN
        return T_UNKNOWN

    def method_ty(self, base, name):
        if base.kind == VARIANT:
            return Ty(VARIANT, base.direct, why=base.why, source=base.source)
        base_name = base.name if base.kind == KNOWN else None
        if name == "get":
            if base_name and base_name.startswith("Dictionary["):
                inner = base_name[base_name.find(",") + 1:-1].strip()
                return Ty(KNOWN, name=inner or None)
            return t_var(True, "Dictionary.get() returns Variant")
        if name in ("pop_back", "pop_front", "back", "front"):
            if base_name and base_name.startswith("Array["):
                return T_KNOWN
            return t_var(True, "Array.%s() returns Variant" % name)
        if name in SIMPLE_METHODS:
            return Ty(KNOWN, name=SIMPLE_METHODS[name])
        return self.index.resolve_method(base, name)

    def subscript_ty(self, base):
        if base.kind == VARIANT:
            return Ty(VARIANT, base.direct, why=base.why, source=base.source)
        if base.kind != KNOWN or not base.name:
            return T_UNKNOWN
        name = base.name
        if name.startswith("Array["):
            return Ty(KNOWN, name=name[name.find("[") + 1:-1].strip() or None)
        if name == "Array":
            return t_var(True, "subscript of an untyped Array returns Variant")
        if name.startswith("Dictionary["):
            return Ty(KNOWN, name=name[name.find(",") + 1:-1].strip() or None)
        if name == "Dictionary":
            return t_var(True, "Dictionary subscript returns Variant")
        if name == "String" or name.startswith("Packed"):
            return T_KNOWN
        return T_UNKNOWN


# --------------------------------------------------------------------------------------
# Scopes
# --------------------------------------------------------------------------------------
class Scope:
    def __init__(self, indent, kind):
        self.indent = indent
        self.kind = kind            # "file" | "class" | "func"
        self.vars = {}              # name -> Ty
        self.parent = None
        self.params = []            # [(name, type_or_None)]
        self.start_line = 0
        self.body_lines = []

    def lookup(self, name):
        scope = self
        while scope is not None:
            if name in scope.vars:
                return scope.vars[name]
            scope = scope.parent
        return None

    def declare(self, name, ty):
        self.vars[name] = ty


# --------------------------------------------------------------------------------------
# The linter
# --------------------------------------------------------------------------------------
VAR_RE = re.compile(r"^(?:@export\s+)?var\s+([A-Za-z_]\w*)\s*(?::=\s*(.+)|:\s*([^=]+?)\s*=\s*(.+)|=\s*(.+)|)$")
FOR_RE = re.compile(r"^for\s+([A-Za-z_]\w*)\s+in\s+(.+?):\s*$")
ASSIGN_RE = re.compile(r"^([A-Za-z_]\w*)\s*=(?!=)\s*(.+)$")
CLASS_RE = re.compile(r"^\s*class\s+([A-Za-z_]\w*)")


class FileLinter:
    def __init__(self, path, index, root):
        self.path = path
        self.index = index
        self.root = root
        self.rel = os.path.relpath(path, root).replace("\\", "/")
        self.findings = []

    def report(self, line, severity, code, message):
        self.findings.append(Finding(self.rel, line, severity, code, message))

    # -- main --------------------------------------------------------------------------
    def run(self):
        try:
            text = open(self.path, encoding="utf-8").read()
        except OSError as exc:
            self.report(1, "review", "GDS000", "cannot read file: %s" % exc)
            return self.findings
        raw_lines = text.split("\n")
        code_lines = strip_literals(raw_lines)
        self.code_lines = code_lines
        self.raw_lines = raw_lines

        file_scope = Scope(-1, "file")
        stack = [file_scope]
        for i, code in enumerate(code_lines):
            lineno = i + 1
            if not code.strip():
                continue
            indent = indent_level(code)
            while len(stack) > 1 and indent <= stack[-1].indent:
                popped = stack.pop()
                if popped.kind == "func":
                    self.check_unused_params(popped, i)
                continue
            scope = stack[-1]

            m = CLASS_RE.match(code)
            if m:
                cls = Scope(indent, "class")
                cls.parent = scope
                stack.append(cls)
                continue

            sig = parse_func(code)
            if sig:
                name, params, ret = sig
                fn = Scope(indent, "func")
                fn.parent = scope
                fn.params = params
                fn.start_line = lineno
                for pname, ptype in params:
                    if ptype is None:
                        fn.declare(pname, t_var(True, "parameter '%s' has no type" % pname))
                    else:
                        fn.declare(pname, self.type_from_name(ptype))
                stack.append(fn)
                continue

            self.statement(scope, lineno, code)
        while len(stack) > 1:
            popped = stack.pop()
            if popped.kind == "func":
                self.check_unused_params(popped, len(code_lines))
        return self.findings

    # -- statements --------------------------------------------------------------------
    def statement(self, scope, lineno, code):
        code = code.strip()
        m = VAR_RE.match(code)
        if m:
            self.declaration(scope, lineno, m)
            return
        m = FOR_RE.match(code)
        if m:
            var, iterable = m.group(1), m.group(2)
            ty = self.eval(iterable, scope)
            scope.declare(var, self.element_ty(ty))
            return
        m = ASSIGN_RE.match(code)
        if m and m.group(1) not in ("var", "func", "class", "if", "elif", "else", "for", "while", "return", "match", "signal", "const", "enum", "static", "extends"):
            # A plain assignment never changes a local's static type in GDScript, so
            # there is nothing to update here.
            return

    def declaration(self, scope, lineno, m):
        name = m.group(1)
        inferred = m.group(2)
        typed = m.group(3)
        plain = m.group(4)
        bare = m.group(5)
        if inferred is not None:
            rhs = inferred.strip()
            ty = self.eval(rhs, scope)
            if ty.is_variant:
                self.report_variant(lineno, self.source_expr(lineno, rhs), ty)
                scope.declare(name, Ty(VARIANT, False, why=ty.why, source=name))
            else:
                scope.declare(name, ty if ty.kind == KNOWN else T_KNOWN)
            return
        if typed is not None:
            scope.declare(name, self.type_from_name(typed.strip()))
            return
        if plain is not None:
            # `var x = value` gives x the static type Variant, whatever the value is.
            scope.declare(name, t_var(True, "declared without a type annotation"))
            return
        if bare is not None:
            scope.declare(name, t_var(True, "declared without a value or type"))
            return

    def source_expr(self, lineno, fallback):
        """The expression as written in the file (string literals intact) for messages.

        The parser works on the literal-stripped text, so echoing that would print
        `ctx.get("")` instead of `ctx.get("e")`.
        """
        raw_lines = getattr(self, "raw_lines", None)
        if not raw_lines or not (0 < lineno <= len(raw_lines)):
            return fallback
        m = re.search(r":=\s*(.+)$", raw_lines[lineno - 1])
        return m.group(1).strip() if m else fallback

    def report_variant(self, lineno, rhs, ty):
        cause = ("propagated from '%s'" % ty.source) if ty.source else (ty.why or "Variant")
        message = "`:=` on a Variant expression (%s): %s" % (cause, rhs[:70])
        if ty.direct:
            self.report(lineno, "error", "GDS101", message)
        elif PROMOTE_NEW_LINT_RULES:
            self.report(lineno, "error", "GDS102", message)
        else:
            self.report(lineno, "review", "GDS102", message)

    def type_from_name(self, name):
        name = name.strip()
        if name == "Variant":
            return t_var(True, "declared as Variant")
        return Ty(KNOWN, name=name)

    def element_ty(self, ty):
        """Element type of an iterable."""
        if ty.kind == VARIANT:
            return Ty(VARIANT, ty.direct, why=ty.why)
        if ty.kind != KNOWN or not ty.name:
            return T_UNKNOWN
        name = ty.name
        if name.startswith("Array["):
            return Ty(KNOWN, name=name[name.find("[") + 1:-1].strip() or None)
        if name == "Array":
            return t_var(True, "loop over an untyped Array yields Variant")
        if name.startswith("Dictionary["):
            inner = name[name.find("[") + 1:-1]
            return Ty(KNOWN, name=inner.split(",")[0].strip() or None)
        if name == "Dictionary":
            return t_var(True, "loop over a Dictionary yields Variant keys")
        if name == "String":
            return Ty(KNOWN, name="String")
        return T_UNKNOWN

    def eval(self, expr, scope):
        tokens = tokenize(expr)
        if not tokens:
            return T_UNKNOWN
        try:
            return ExprParser(tokens, scope, self.index).parse()
        except RecursionError:
            return T_UNKNOWN

    # -- R2: unused parameters ----------------------------------------------------------
    def check_unused_params(self, fn, end_index):
        body = "\n".join(self.code_lines[fn.start_line:end_index])
        for pname, ptype in fn.params:
            if pname.startswith("_"):
                continue
            if re.search(r"(?<![\w.])" + re.escape(pname) + r"(?![\w])", body):
                continue
            self.report(fn.start_line, "review", "GDS201",
                        "parameter '%s' is never used in this function" % pname)


# --------------------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------------------
def gd_files(root):
    out = []
    for path in glob.glob(os.path.join(root, "**", "*.gd"), recursive=True):
        norm = path.replace("\\", "/")
        if "/.godot/" in norm or "/.godot-bin/" in norm:
            continue
        out.append(path)
    return sorted(out)


def lint_file(path, index, root):
    return FileLinter(path, index, root).run()


def lint_project(root, promote=None):
    """Lint every .gd file under `root`. -> list[Finding]"""
    if promote is not None:
        global PROMOTE_NEW_LINT_RULES
        PROMOTE_NEW_LINT_RULES = promote
    index = ProjectIndex(root)
    findings = []
    for path in gd_files(root):
        findings.extend(lint_file(path, index, root))
    return findings


def main(argv):
    args = list(argv)
    promote = None
    as_json = False
    if "--promote" in args:
        args.remove("--promote")
        promote = True
    if "--json" in args:
        args.remove("--json")
        as_json = True
    root = ROOT
    targets = [a for a in args if not a.startswith("-")]
    index = ProjectIndex(root)
    findings = []
    if targets:
        for t in targets:
            path = t if os.path.isabs(t) else os.path.join(root, t)
            findings.extend(lint_file(path, index, root))
    else:
        for path in gd_files(root):
            findings.extend(lint_file(path, index, root))
    errors = [f for f in findings if f.severity == "error"]
    reviews = [f for f in findings if f.severity == "review"]
    if as_json:
        import json
        print(json.dumps([
            {"path": f.path, "line": f.line, "severity": f.severity,
             "code": f.code, "message": f.message} for f in findings]))
        return 1 if errors else 0
    for f in errors:
        print("ERROR:", f)
    for f in reviews:
        print("review:", f)
    print("gdscript_lint: %d error(s), %d review item(s)" % (len(errors), len(reviews)))
    return 1 if errors else 0


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
