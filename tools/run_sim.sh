#!/bin/bash
# usage: run_sim.sh <design dir> [clk3 period ns] [npat]
D=${1:-designs/v1}; P=${2:-20.7}; N=${3:-100}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/$(basename $D)_$P; mkdir -p $W; cd $W
cp $ROOT/00_TESTBED/pattern_*.dat .
iverilog -g2012 -o sim.vvp -DCLK3_PERIOD=$P -DNPAT=$N \
  $ROOT/00_TESTBED/TESTBED.v $ROOT/00_TESTBED/PATTERN.v $ROOT/common/NTT_TOP.v \
  $ROOT/common/NDFF_syn.v $ROOT/common/NDFF_BUS_syn.v $ROOT/04_MEM/DUAL_64X16X1BM1.v \
  $ROOT/$D/DESIGN_MODULE.v $ROOT/$D/Handshake_syn.v $ROOT/$D/FIFO_syn.v || exit 1
vvp -n sim.vvp | grep -v "^VCD" | tail -${TAIL:-6}
