#!/bin/bash
D=${1:-designs/v5}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/tools/lib/nangate45.lib
$ROOT/tools/stage.sh $D $ROOT/build/stage_syn
cd $ROOT/build/stage_syn
yosys -q -p "
read_verilog -sv -I$ROOT/build/stage_syn $ROOT/tools/sram_bb.v $ROOT/build/stage_syn/NTT_TOP.v
hierarchy -top NTT_TOP
proc; opt -purge
synth -top NTT_TOP
opt -purge
dfflibmap -liberty $LIB
abc -liberty $LIB
opt_clean -purge
tee -o $ROOT/build/syn/hier.stat stat -liberty $LIB
" >/dev/null 2>&1
grep -E "^=== |Chip area" $ROOT/build/syn/hier.stat | sed 's/\$paramod\$[0-9a-f]*\\//' | paste - - | sed 's/  */ /g'
