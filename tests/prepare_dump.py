from pathlib import Path
import re
import argparse

def process_verilog_file(v_file: Path):
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
    vcd_path = tmppath.parent / tmppath.stem / f"{tmppath.stem}.vcd"
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