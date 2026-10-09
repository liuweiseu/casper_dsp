"""Check (and dump) the HDL-Simulink Mapping blocks in rtl/.

Each RTL module that has a casper_library Simulink block records its
differences from that block in its header comment, between

    // @simulink-mapping begin
    ...
    // @simulink-mapping end

The lines in between are TOML once the leading "// " (or "//") is removed:

    block = 'casper_library_ffts.slx/biplex_core'   # library file / block
    deviations = ['free-text behavioural differences', ...]

    [params.QUANTIZATION]          # numeric HDL value -> mask option text
    mask = 'quantization'          # mask variable name
    type = 'popup'                 # popup | checkbox | edit
    hdl_unsupported = [2]          # optional: values the HDL rejects
    note = '...'                   # optional
    [params.QUANTIZATION.values]   # popup / checkbox only
    0 = 'Truncate'                 # option text verbatim (spaces, case); for a
                                   # string HDL parameter the keys are its values

    An 'edit' (free-text mask field) entry has no values table; it records
    the mask name of an HDL parameter whose type or meaning differs (note).
    It may carry an expr giving the mask value from the HDL parameters:

    [params.ADDR_WIDTH]
    mask = 'depth'
    type = 'edit'
    expr = '2**ADDR_WIDTH'         # mask value = this expression

    expr is a constant expression in Verilog syntax over the parameters of
    the same module (an unset parameter takes its HDL default). Operators:
    + - * / % ** << >>, < <= > >= == !=, && || !, unary + - ~, ?:,
    parentheses, $clog2(x); integer and real literals. Evaluation follows
    Verilog: integer arithmetic (/ and % truncate toward zero) unless an
    operand is real, e.g. INIT_VAL / 2.0**BIN_P is real. values and expr
    are mutually exclusive. parse_expr() / eval_expr() below implement it.

    [mask_set.<mask param>]        # sets a mask parameter no HDL param maps to;
    value = 'Unsigned'             # exactly one of: value = <TOML scalar>,
                                   # expr = '<expr>', template = 'text {expr}'
                                   # (each {...} is an expr) or
                                   # from_mem = '<HDL param>' ($readmemh file
                                   # named by that parameter -> "[w0 w1 ...]")
    [mask_set.<mask param>.else]   # from_mem only, optional: one value / expr /
    template = 'zeros(1,{2**N})'   # template entry used when the file name is ""

    [hdl_only]                     # HDL parameter -> why the mask lacks it
    [mask_missing]                 # mask parameter -> why the HDL lacks it
    [ports]                        # optional order / note strings
    [ports.renamed]                # HDL port -> Simulink port name(s)
    [ports.missing]                # Simulink port -> why the HDL lacks it
    [ports.extra]                  # HDL port -> why Simulink lacks it

--dump also adds, per module, "hdl_defaults": {PARAM: value}, the default
of every HDL parameter evaluated from the RTL (numbers, strings; defaults
that reference earlier parameters are evaluated in order). A default that
cannot be evaluated statically is omitted. It is not part of the comment.

Usage:
    python3 tools/check_simulink_mapping.py          # validate, exit 1 on errors
    python3 tools/check_simulink_mapping.py --dump   # print all blocks as JSON
    python3 tools/check_simulink_mapping.py --dump -o out/mapping.json
                                                     # save the JSON to a file
    python3 tools/check_simulink_mapping.py -o out/check.txt
                                                     # save the check report

Run from any directory: paths are resolved from this file (tools/ -> repository root).
"""

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEGIN, END = "@simulink-mapping begin", "@simulink-mapping end"
TOP_KEYS = {"block", "deviations", "params", "mask_set", "hdl_only", "mask_missing", "ports"}
MASK_SET_KINDS = ("value", "expr", "template", "from_mem")
PARAM_KEYS = {"mask", "type", "values", "hdl_unsupported", "note", "expr"}
PORT_KEYS = {"order", "note", "renamed", "missing", "extra"}


# ── expr: Verilog-style constant expressions ────────────────────────────────

_TOKEN = re.compile(r"""\s*(?:
    (?P<real>\d+\.\d*(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+)
  | (?P<int>\d+)
  | (?P<func>\$clog2)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>\*\*|<<|>>|<=|>=|==|!=|&&|\|\||[-+*/%<>!~?:()])
)""", re.X)

# binary operators by precedence, lowest first (Verilog order)
_BINARY = [["||"], ["&&"], ["==", "!="], ["<", "<=", ">", ">="], ["<<", ">>"],
           ["+", "-"], ["*", "/", "%"]]


def _tokens(text):
    pos, out = 0, []
    text = text.rstrip()
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m or m.end() == pos:
            raise ValueError(f"bad character at {text[pos:]!r}")
        kind = m.lastgroup
        out.append((kind, m.group(kind)))
        pos = m.end()
    return out


def parse_expr(text):
    """Parse expr into a nested-tuple AST; raises ValueError on a syntax error.

    Nodes: ('num', value), ('name', id), ('un', op, x), ('bin', op, a, b),
    ('cond', c, a, b), ('clog2', x).
    """
    toks = _tokens(text)
    pos = 0

    def peek():
        return toks[pos][1] if pos < len(toks) else None

    def take(expected=None):
        nonlocal pos
        if pos >= len(toks):
            raise ValueError("unexpected end of expression")
        tok = toks[pos]
        if expected is not None and tok[1] != expected:
            raise ValueError(f"expected {expected!r}, got {tok[1]!r}")
        pos += 1
        return tok

    def cond():
        c = binary(0)
        if peek() == "?":
            take("?")
            a = cond()
            take(":")
            return ("cond", c, a, cond())
        return c

    def binary(level):
        if level == len(_BINARY):
            return power()
        node = binary(level + 1)
        while peek() in _BINARY[level]:
            op = take()[1]
            node = ("bin", op, node, binary(level + 1))
        return node

    def power():                                   # ** binds tighter than * / %
        base = unary()
        if peek() == "**":
            take()
            return ("bin", "**", base, power())   # right-associative
        return base

    def unary():
        if peek() in ("+", "-", "!", "~"):
            return ("un", take()[1], unary())
        return atom()

    def atom():
        kind, val = take()
        if kind == "int":
            return ("num", int(val))
        if kind == "real":
            return ("num", float(val))
        if kind == "name":
            return ("name", val)
        if kind == "func":
            take("(")
            x = cond()
            take(")")
            return ("clog2", x)
        if val == "(":
            x = cond()
            take(")")
            return x
        raise ValueError(f"unexpected {val!r}")

    node = cond()
    if pos != len(toks):
        raise ValueError(f"unexpected {toks[pos][1]!r}")
    return node


def expr_names(node):
    """Parameter names an AST references."""
    if node[0] == "name":
        return {node[1]}
    return set().union(*(expr_names(x) for x in node[1:] if isinstance(x, tuple)))


def eval_expr(text_or_node, params):
    """Evaluate expr with {parameter: value}; Verilog int/real semantics."""
    node = parse_expr(text_or_node) if isinstance(text_or_node, str) else text_or_node

    def ev(n):
        t = n[0]
        if t == "num":
            return n[1]
        if t == "name":
            if n[1] not in params:
                raise KeyError(f"no value for parameter {n[1]}")
            return params[n[1]]
        if t == "clog2":
            x = int(ev(n[1]))
            return 0 if x <= 1 else (x - 1).bit_length()
        if t == "cond":
            return ev(n[2]) if ev(n[1]) else ev(n[3])
        if t == "un":
            x = ev(n[2])
            return {"+": x, "-": -x, "!": int(not x), "~": ~int(x)}[n[1]]
        op, a, b = n[1], ev(n[2]), ev(n[3])
        real = isinstance(a, float) or isinstance(b, float)
        if op == "/":
            return a / b if real else int(a / b) if b else 0
        if op == "%":
            return (a - b * int(a / b)) if b else 0
        if op == "**":
            return float(a) ** b if real else (a ** b if b >= 0 else 0)
        return {"+": lambda: a + b, "-": lambda: a - b, "*": lambda: a * b,
                "<<": lambda: int(a) << int(b), ">>": lambda: int(a) >> int(b),
                "<": lambda: int(a < b), "<=": lambda: int(a <= b),
                ">": lambda: int(a > b), ">=": lambda: int(a >= b),
                "==": lambda: int(a == b), "!=": lambda: int(a != b),
                "&&": lambda: int(bool(a) and bool(b)),
                "||": lambda: int(bool(a) or bool(b))}[op]()

    return ev(node)


_SIZED = re.compile(r"(\d+)?\s*'[sS]?([bBoOdDhH])\s*([0-9a-fA-F_]+)")
_UNSIZED_FILL = re.compile(r"'([01])\b")


def _verilog_literals(text):
    """Rewrite Verilog based literals (16'h1A4E, 'd5, '1) as plain integers."""
    def based(m):
        size, base, digits = m.group(1), m.group(2).lower(), m.group(3).replace("_", "")
        value = int(digits, {"b": 2, "o": 8, "d": 10, "h": 16}[base])
        return str(value & ((1 << int(size)) - 1) if size else value)
    return _UNSIZED_FILL.sub(r"\1", _SIZED.sub(based, text))


def _split_top(text):
    """Split on commas outside (), [] and {}."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    return out + [cur]


def hdl_defaults(text):
    """{parameter: default} of the module header, evaluated statically.

    Integer / real / string defaults and expressions over earlier parameters
    (operators as in expr, plus Verilog based literals) are evaluated; any
    other default (a function call, an unknown name, ...) is omitted.
    """
    t = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    m = re.search(r"^\s*module\s+\w+\s*#\s*\(", t, re.M)
    if not m:
        return {}
    depth, i = 1, m.end()
    while depth and i < len(t):
        depth += {"(": 1, ")": -1}.get(t[i], 0)
        i += 1
    out = {}
    for item in _split_top(t[m.end():i - 1]):
        d = re.match(r"\s*parameter\s+(?:(int|integer|real|string|bit|logic)\s+)?"
                     r"(?:\[[^\]]*\]\s*)?(\w+)\s*=\s*(.*?)\s*$", item, re.S)
        if not d:
            continue
        typ, name, expr = d.groups()
        try:
            if re.fullmatch(r'"[^"]*"', expr):
                out[name] = expr[1:-1]
                continue
            value = eval_expr(_verilog_literals(expr), out)
            if typ == "real":
                value = float(value)
            elif typ in ("int", "integer") and isinstance(value, float):
                value = int(value)
            out[name] = value
        except (ValueError, KeyError, TypeError, ZeroDivisionError, OverflowError):
            pass
    return out


def rtl_files():
    return sorted(p for p in (ROOT / "rtl").rglob("*")
                  if p.suffix in (".v", ".sv") and "scripts" not in p.parts)


def extract(text):
    """Return the TOML text of the mapping block, or None if there is none."""
    lines = text.split("\n")
    b = [i for i, l in enumerate(lines) if l.strip() == f"// {BEGIN}"]
    e = [i for i, l in enumerate(lines) if l.strip() == f"// {END}"]
    if not b and not e:
        return None
    if len(b) != 1 or len(e) != 1 or e[0] < b[0]:
        raise ValueError(f"need exactly one '{BEGIN}' ... '{END}' pair")
    body = []
    for l in lines[b[0] + 1:e[0]]:
        if not l.startswith("//"):
            raise ValueError(f"non-comment line inside the block: {l!r}")
        body.append(l[3:] if l.startswith("// ") else l[2:])
    return "\n".join(body)


def declared(text):
    """HDL parameter and port names declared in the module header."""
    t = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    t = re.sub(r"//.*", "", t)
    m = re.search(r"\bmodule\s+\w+\s*(#\s*\((.*?)\))?\s*\((.*?)\);", t, re.S)
    decls = re.findall(r"parameter\s+(int\s+|string\s+|integer\s+|real\s+)?(\w+)\s*=",
                       m.group(2) or "") if m else []
    params = {n for _, n in decls}
    strings = {n for t, n in decls if t.strip() == "string"}
    ports = set()
    for decl in re.split(r",(?![^\[]*\])", m.group(3) if m else ""):
        pm = re.search(r"([A-Za-z_]\w*)\s*((?:\[[^\]]*\]\s*)*)(?:=\s*[^,]*)?$", decl.strip())
        if pm:
            ports.add(pm.group(1))
    return params, ports, strings


def _check_expr(where, text, params):
    """Errors of one expr string (parse + only module parameters)."""
    try:
        unknown = expr_names(parse_expr(text)) - params
        return [f"{where}: expr references {sorted(unknown)}, not parameters "
                "of the module"] if unknown else []
    except (ValueError, TypeError) as e:
        return [f"{where}: expr does not parse: {e}"]


def _check_mask_set_entry(where, e, params, allow_from_mem):
    errs = []
    if not isinstance(e, dict):
        return [f"{where}: must be a table"]
    kinds = [k for k in MASK_SET_KINDS if k in e]
    extra = set(e) - set(MASK_SET_KINDS) - ({"else"} if allow_from_mem else set())
    if extra:
        errs.append(f"{where}: unknown key(s) {sorted(extra)}")
    if len(kinds) != 1:
        return errs + [f"{where}: needs exactly one of {', '.join(MASK_SET_KINDS)}"]
    kind = kinds[0]
    if kind == "from_mem" and not allow_from_mem:
        errs.append(f"{where}: an else entry cannot be from_mem")
    elif kind == "value" and isinstance(e["value"], (dict, list)):
        errs.append(f"{where}: value must be a scalar")
    elif kind == "expr":
        errs += _check_expr(where, e["expr"], params)
    elif kind == "template":
        if not isinstance(e["template"], str):
            errs.append(f"{where}: template must be a string")
        else:
            for part in re.findall(r"\{([^{}]*)\}", e["template"]):
                errs += _check_expr(where, part, params)
            if re.sub(r"\{[^{}]*\}", "", e["template"]).count("{") or \
               re.sub(r"\{[^{}]*\}", "", e["template"]).count("}"):
                errs.append(f"{where}: unbalanced braces in template")
    elif kind == "from_mem":
        if e["from_mem"] not in params:
            errs.append(f"{where}: from_mem names '{e['from_mem']}', not a parameter of the module")
    if "else" in e:
        if kind != "from_mem":
            errs.append(f"{where}: else is only allowed with from_mem")
        else:
            errs += _check_mask_set_entry(f"{where}.else", e["else"], params, False)
    return errs


def check(path, data, text):
    errs = []
    params, ports, strings = declared(text)
    for k in set(data) - TOP_KEYS:
        errs.append(f"unknown key '{k}'")
    if not isinstance(data.get("block"), str) or "/" not in data["block"]:
        errs.append("block must be '<library>.slx/<block>'")
    if not isinstance(data.get("deviations", []), list):
        errs.append("deviations must be a list of strings")
    for name, p in data.get("params", {}).items():
        if name not in params:
            errs.append(f"params.{name}: not a parameter of the module")
        for k in set(p) - PARAM_KEYS:
            errs.append(f"params.{name}: unknown key '{k}'")
        if p.get("type") not in ("popup", "checkbox", "edit"):
            errs.append(f"params.{name}: type must be popup, checkbox or edit")
        if not isinstance(p.get("mask"), str):
            errs.append(f"params.{name}: mask (mask variable name) missing")
        vals = p.get("values", {})
        if "expr" in p:
            if vals:
                errs.append(f"params.{name}: values and expr are mutually exclusive")
            try:
                unknown = expr_names(parse_expr(p["expr"])) - params
                if unknown:
                    errs.append(f"params.{name}: expr references {sorted(unknown)}, "
                                "not parameters of the module")
            except (ValueError, TypeError) as e:
                errs.append(f"params.{name}: expr does not parse: {e}")
        if p.get("type") == "edit":
            if vals:
                errs.append(f"params.{name}: an edit field has no values table")
        elif not vals or not all((k.lstrip("-").isdigit() or name in strings) and isinstance(v, str)
                                 for k, v in vals.items()):
            errs.append(f"params.{name}: values must map integers (or, for a string "
                        "parameter, its string values) to option strings")
    masks_of_params = {p.get("mask") for p in data.get("params", {}).values()}
    for m, e in data.get("mask_set", {}).items():
        if m in masks_of_params:
            errs.append(f"mask_set.{m}: already set through a params entry")
        errs += _check_mask_set_entry(f"mask_set.{m}", e, params, True)
    for name in data.get("hdl_only", {}):
        if name not in params:
            errs.append(f"hdl_only.{name}: not a parameter of the module")
    for tbl in ("hdl_only", "mask_missing"):
        if not all(isinstance(v, str) for v in data.get(tbl, {}).values()):
            errs.append(f"{tbl}: values must be strings (the reason)")
    pt = data.get("ports", {})
    for k in set(pt) - PORT_KEYS:
        errs.append(f"ports: unknown key '{k}'")
    for name in list(pt.get("renamed", {})) + list(pt.get("extra", {})):
        if name not in ports:
            errs.append(f"ports: '{name}' is not a port of the module")
    for name in pt.get("missing", {}):
        if name in ports:
            errs.append(f"ports.missing.{name}: the module does have this port")
    return [f"{path.relative_to(ROOT)}: {e}" for e in errs]


def load_all():
    """{module name: parsed mapping block} for every RTL file that has one."""
    out = {}
    for f in rtl_files():
        body = extract(f.read_text())
        if body is not None:
            out[f.stem] = tomllib.loads(body)
    return out


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Check (and dump) the HDL-Simulink Mapping blocks in rtl/.")
    ap.add_argument("--dump", action="store_true",
                    help="output every mapping block as JSON {rtl path: block} instead of the check report")
    ap.add_argument("-o", "--output", type=Path, metavar="FILE",
                    help="write the output (JSON with --dump, else the check report) to FILE; "
                         "missing parent directories are created")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    errors, blocks = [], {}
    for f in rtl_files():
        text = f.read_text()
        try:
            body = extract(text)
            if body is None:
                continue
            data = tomllib.loads(body)
        except (ValueError, tomllib.TOMLDecodeError) as e:
            errors.append(f"{f.relative_to(ROOT)}: {e}")
            continue
        blocks[str(f.relative_to(ROOT))] = dict(data, hdl_defaults=hdl_defaults(text))
        errors += check(f, data, text)
    summary = f"{len(blocks)} mapping blocks, {len(errors)} errors"
    if args.dump:
        out = json.dumps(blocks, indent=1, ensure_ascii=False) + "\n"
    else:
        out = "".join(e + "\n" for e in errors) + summary + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out, encoding="utf-8")
        for e in errors:                 # still show problems on the terminal
            print(e, file=sys.stderr)
        print(f"{summary}; written to {args.output}")
    else:
        print(out, end="")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
