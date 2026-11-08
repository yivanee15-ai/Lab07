#!/bin/bash
# per-module area (hierarchy kept).  usage: synth_hier.sh designs/vN
D=${1:-designs/v2}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/tools/lib/nangate45.lib
yosys -q -p "
read_verilog -sv $ROOT/common/NTT_TOP.v $ROOT/common/NDFF_syn.v $ROOT/common/NDFF_BUS_syn.v $ROOT/tools/sram_bb.v $ROOT/$D/DESIGN_MODULE.v $ROOT/$D/Handshake_syn.v $ROOT/$D/FIFO_syn.v
hierarchy -top NTT_TOP
proc; opt -purge
synth -top NTT_TOP
opt -purge
dfflibmap -liberty $LIB
abc -liberty $LIB
opt_clean -purge
tee -o $ROOT/build/syn/hier.stat stat -liberty $LIB
" >/dev/null 2>&1
python3 - <<PY
import re
s=open("$ROOT/build/syn/hier.stat").read()
for m in re.finditer(r"=== (\S+) ===(.*?)Chip area for module '\\\\(\S+)': ([0-9.]+)",s,re.S):
    name=m.group(1); body=m.group(2); area=float(m.group(4))
    ff=sum(int(x) for x in re.findall(r"DFF\w*\s+(\d+)",body))
    mux=sum(int(x) for x in re.findall(r"MUX2_X1\s+(\d+)",body))
    print("%-14s area %9.1f  FF %5d  MUX2 %5d"%(name,area,ff,mux))
PY
