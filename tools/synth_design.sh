#!/bin/bash
# usage: synth_design.sh designs/vN  -> area/delay proxy of NTT_TOP (SRAM macro excluded)
D=${1:-designs/v5}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
$ROOT/tools/stage.sh $D $ROOT/build/stage_syn
cd $ROOT/build/stage_syn
$ROOT/tools/synth.sh NTT_TOP 4000 -I$ROOT/build/stage_syn $ROOT/tools/sram_bb.v $ROOT/build/stage_syn/NTT_TOP.v 2>&1 | grep -E "Chip area|DFF|Delay ="
