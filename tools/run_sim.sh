#!/bin/bash
# usage: run_sim.sh <design dir> [clk3 period ns] [npat]      (env: SIMARGS, TAIL)
D=${1:-designs/v5}; P=${2:-20.7}; N=${3:-100}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/$(basename $D)_$P; mkdir -p $W; cd $W
$ROOT/tools/stage.sh $D $W/stage
cp $ROOT/00_TESTBED/pattern_*.dat .
grep -v 'fsdb' $ROOT/00_TESTBED/TESTBED.v > $W/TESTBED_sim.v      # iverilog has no fsdb tasks
iverilog -g2012 -o sim.vvp -DRTL -DCLK3_PERIOD=$P -DNPAT=$N -I$ROOT/00_TESTBED -I$W/stage \
  $W/TESTBED_sim.v $ROOT/04_MEM/DUAL_64X16X1BM1.v || exit 1
vvp -n sim.vvp $SIMARGS | grep -v "^VCD" | tail -${TAIL:-12}
