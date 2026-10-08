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

    [hdl_only]                     # HDL parameter -> why the mask lacks it
    [mask_missing]                 # mask parameter -> why the HDL lacks it
    [ports]                        # optional order / note strings
    [ports.renamed]                # HDL port -> Simulink port name(s)
    [ports.missing]                # Simulink port -> why the HDL lacks it
    [ports.extra]                  # HDL port -> why Simulink lacks it

Usage:
    python3 tools/check_simulink_mapping.py          # validate, exit 1 on errors
    python3 tools/check_simulink_mapping.py --dump   # print all blocks as JSON

Run from any directory: paths are resolved from this file (tools/ -> repository root).
"""

import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEGIN, END = "@simulink-mapping begin", "@simulink-mapping end"
TOP_KEYS = {"block", "deviations", "params", "hdl_only", "mask_missing", "ports"}
PARAM_KEYS = {"mask", "type", "values", "hdl_unsupported", "note"}
PORT_KEYS = {"order", "note", "renamed", "missing", "extra"}


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
        if p.get("type") == "edit":
            if vals:
                errs.append(f"params.{name}: an edit field has no values table")
        elif not vals or not all((k.lstrip("-").isdigit() or name in strings) and isinstance(v, str)
                                 for k, v in vals.items()):
            errs.append(f"params.{name}: values must map integers (or, for a string "
                        "parameter, its string values) to option strings")
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


def main():
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
        blocks[str(f.relative_to(ROOT))] = data
        errors += check(f, data, text)
    if "--dump" in sys.argv:
        print(json.dumps(blocks, indent=1, ensure_ascii=False))
        return 0 if not errors else 1
    for e in errors:
        print(e)
    print(f"{len(blocks)} mapping blocks, {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
