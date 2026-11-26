#!/bin/bash
# Run tb_xilinx_equiv.sv with Vivado xsim: checks that the PLATFORM="XILINX"
# (XPM) implementations of single_port_ram, dual_port_ram, rom and delay_bram
# match the PLATFORM="GENERIC" ones cycle by cycle, for several configurations.
#
# Requires a local Vivado install (xsim + XPM sources); not part of the Docker
# / cocotb flow. Usage:
#   platform/xilinx/sim/run_xsim_equiv.sh [VIVADO_DIR]
# VIVADO_DIR defaults to /tools/Xilinx/Vivado/2021.1 (the version
# tests/simulation.toml's [xilinx] lib_path refers to).
set -e

VIVADO_DIR="${1:-/tools/Xilinx/Vivado/2021.1}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="${XSIM_WORK:-$ROOT/tests/results/xsim_equiv}"

# shellcheck disable=SC1091
source "$VIVADO_DIR/settings64.sh"
mkdir -p "$WORK"
cd "$WORK"

SOURCES=(
    "$VIVADO_DIR/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv"
    "$ROOT/rtl/BasicModules/register.sv"
    "$ROOT/rtl/BasicModules/counter.sv"
    "$ROOT/rtl/Delays/delay_srl.sv"
    "$ROOT/rtl/Delays/pipeline.sv"
    "$ROOT/rtl/Delays/single_port_ram.sv"
    "$ROOT/rtl/Delays/dual_port_ram.sv"
    "$ROOT/rtl/Delays/rom.sv"
    "$ROOT/rtl/Delays/delay_bram.sv"
    "$ROOT/platform/xilinx/single_port_ram_xilinx.sv"
    "$ROOT/platform/xilinx/dual_port_ram_xilinx.sv"
    "$ROOT/platform/xilinx/rom_xilinx.sv"
    "$ROOT/platform/xilinx/sim/tb_xilinx_equiv.sv"
)
xvlog -sv "${SOURCES[@]}" > xvlog.log

# DATA_WIDTH ADDR_WIDTH DELAY_LEN
CONFIGS=(
    "8 4 16"
    "16 6 5"
    "1 3 2"
    "18 8 100"
    "36 10 1000"
)

status=0
for cfg in "${CONFIGS[@]}"; do
    read -r dw aw dl <<< "$cfg"
    snap="tb_${dw}_${aw}_${dl}"
    mem="$WORK/rom_${dw}_${aw}.mem"
    python3 - "$dw" "$aw" "$mem" <<'EOF'
import random, sys
dw, aw, path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
rng = random.Random(f"xsim-rom-{dw}-{aw}")
digits = (dw + 3) // 4
with open(path, "w") as f:
    for _ in range(1 << aw):
        f.write(f"{rng.randrange(1 << dw):0{digits}x}\n")
EOF
    xelab -debug off -L xpm tb_xilinx_equiv -s "$snap" \
        -generic_top "DATA_WIDTH=$dw" -generic_top "ADDR_WIDTH=$aw" \
        -generic_top "DELAY_LEN=$dl" -generic_top "INIT_FILE=$mem" \
        > "xelab_$snap.log"
    xsim "$snap" -R > "xsim_$snap.log"
    grep -E "RESULT|MISMATCH" "xsim_$snap.log"
    grep -q EQUIV_PASS "xsim_$snap.log" || status=1
done

if [ $status -eq 0 ]; then echo "ALL XSIM EQUIVALENCE CHECKS PASSED"; else echo "XSIM EQUIVALENCE CHECK FAILED"; fi
exit $status
