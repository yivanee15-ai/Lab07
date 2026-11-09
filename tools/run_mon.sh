#!/bin/bash
D=${1:-designs/v5}; P=${2:-20.7}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/mon_$(basename $D); mkdir -p $W; cd $W; cp $ROOT/00_TESTBED/pattern_*.dat .
$ROOT/tools/stage.sh $D $W/stage
grep -v 'fsdb' $ROOT/00_TESTBED/TESTBED.v > $W/TESTBED_sim.v
iverilog -g2012 -o mon.vvp -DRTL -DCLK3_PERIOD=$P -DNPAT=2 -I$ROOT/00_TESTBED -I$W/stage $ROOT/tools/mon.v $W/TESTBED_sim.v $ROOT/04_MEM/DUAL_64X16X1BM1.v && vvp -n mon.vvp 2>&1 | grep -E "dvalid|winc|out_valid|LATENCY" | head -30
