from pathlib import Path
import re, os
import argparse
from typing import Optional, Union
PathLike = Union[str, os.PathLike]

def process_verilog_file(v_file: Path, id=-1):
    text = v_file.read_text()

    # 1. get the module name
    module_match = re.search(r'\bmodule\s+(\w+)', text)
    if not module_match:
        print(f"[WARN] No module found in {v_file}")
        return
    module_name = module_match.group(1)
    lines = text.splitlines()

    # 2. look for endmodule
    endmodule_idx = None
    for i in range(len(lines) - 1, -1, -1):
        if re.match(r'\s*endmodule\b', lines[i]):
            endmodule_idx = i
            break
    if endmodule_idx is None:
        print(f"[WARN] No endmodule found in {v_file}")
        return

    # 3. create the dump block
    # the vcd file will be written to tests/results/xxx
    vpath = Path(v_file)
    tmppath = Path(*("tests/results" if part == "rtl" else part for part in vpath.parts))
    if id == -1:
        vcd_path = tmppath.parent / tmppath.stem / f"{tmppath.stem}.vcd"
    else:
        vcd_path = tmppath.parent / tmppath.stem / f"{tmppath.stem}_{id}.vcd"
    vcd_path.parent.mkdir(parents=True, exist_ok=True)
    vcd_path = str(vcd_path)
    dump_block = [
        "initial begin",
        f'    $dumpfile("{vcd_path}");',
        f"    $dumpvars(0, {module_name});",
        "end"
    ]

    # 4. insert the dump block
    new_lines = (
        lines[:endmodule_idx]
        + dump_block
        + lines[endmodule_idx:]
    )

    # write the data back
    v_file.write_text("\n".join(new_lines))
    print(f"[OK] Updated {v_file}")


def scan_directory(target_dir: Path):
    for v_file in target_dir.rglob("*.v"):
        process_verilog_file(v_file)
    for sv_file in target_dir.rglob("*.sv"):
        process_verilog_file(sv_file)

from pathlib import Path

from pathlib import Path
import os
from typing import List

def find_file(keyword: str, root: str | os.PathLike = ".") -> List[Path]:
    root_path = Path(root)
    results: List[Path] = []
    for path in root_path.rglob("*"):
        if path.is_file() and keyword in path.name:
            results.append(path.resolve())
    return results

def replace_vcd_filename(filepath: str | os.PathLike, new_filename: str):
    path = Path(filepath)
    text = path.read_text()
    new_text = re.sub(r"\b[\w\-.]+\.vcd\b", new_filename, text)
    path.write_text(new_text)

def main():
    parser = argparse.ArgumentParser(
        description="Scan directory recursively and process .v files"
    )
    parser.add_argument(
        "--dir",
        type=Path,
        help="Target directory to scan"
    )
    args = parser.parse_args()
    target_dir = args.dir.resolve()
    scan_directory(target_dir)

if __name__ == "__main__":
    main()