#!/bin/bash
# usage: stage.sh designs/vN <stage dir>  -> course-style layout: DESIGN_module.v, synchronizer/*.v, NTT_TOP.v
ROOT=$(cd "$(dirname "$0")/.." && pwd)
rm -rf $2; mkdir -p $2/synchronizer
cp $ROOT/$1/DESIGN_module.v $2/
cp $ROOT/$1/synchronizer/*.v $2/synchronizer/
cp $ROOT/common/NDFF_syn.v $ROOT/common/NDFF_BUS_syn.v $2/synchronizer/
cp $ROOT/common/NTT_TOP.v $2/
