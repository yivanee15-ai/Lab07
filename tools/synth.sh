#!/bin/bash
# Rough area / delay proxy with yosys + abc on the open Nangate45 liberty.
# usage: synth.sh <top module> <abc target ps> <verilog files...>
TOP=$1; D=${2:-5000}; shift 2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/tools/lib/nangate45.lib
mkdir -p $ROOT/build/syn
yosys -q -l $ROOT/build/syn/$TOP.log -p "
read_verilog -sv $*
hierarchy -top $TOP
proc; flatten; opt -purge
synth -top $TOP -flatten
opt -purge
dfflibmap -liberty $LIB
abc -liberty $LIB -script $ROOT/tools/abc_timing.script -showtmp
opt_clean -purge
tee -o $ROOT/build/syn/$TOP.stat stat -liberty $LIB
" 2>&1 | tail -3
grep -E "Chip area|cells$|DFF|Delay" $ROOT/build/syn/$TOP.stat $ROOT/build/syn/$TOP.log | head
grep -E "WireLoad|Path|Start-point|End-point" $ROOT/build/syn/$TOP.log | head -8
