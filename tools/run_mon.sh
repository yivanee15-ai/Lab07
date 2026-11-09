#!/bin/bash
D=${1:-designs/v2}; P=${2:-20.7}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/mon_$(basename $D); mkdir -p $W; cd $W; cp $ROOT/00_TESTBED/pattern_*.dat .
grep -v 'fsdb' $ROOT/00_TESTBED/TESTBED.v > $W/TESTBED_sim.v
iverilog -g2012 -o mon.vvp -DCLK3_PERIOD=$P -DNPAT=2 $ROOT/tools/mon.v -DRTL -I$ROOT/00_TESTBED -I$ROOT/common $W/TESTBED_sim.v $ROOT/common/NDFF_syn.v $ROOT/common/NDFF_BUS_syn.v $ROOT/04_MEM/DUAL_64X16X1BM1.v $ROOT/$D/DESIGN_MODULE.v $ROOT/$D/Handshake_syn.v $ROOT/$D/FIFO_syn.v && vvp -n mon.vvp 2>&1 | grep -E "dvalid|winc|out_valid|LATENCY" | head -30
