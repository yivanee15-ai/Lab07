#!/bin/bash
# usage: synth_design.sh designs/vN  -> area breakdown of NTT_TOP (SRAM macro excluded)
D=${1:-designs/v2}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
$ROOT/tools/synth.sh NTT_TOP 4000 $ROOT/common/NTT_TOP.v $ROOT/common/NDFF_syn.v $ROOT/common/NDFF_BUS_syn.v \
   $ROOT/tools/sram_bb.v $ROOT/$D/DESIGN_MODULE.v $ROOT/$D/Handshake_syn.v $ROOT/$D/FIFO_syn.v 2>&1 | grep -E "Chip area|DFF|Delay ="
