#!/bin/bash
# usage: tools/report.sh  -> prints | design | latency | area | ... | table (markdown)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
echo "| design | latency @20.7ns (ns) | logic area (Nangate45 um^2, SRAM excl.) | FF | abc worst comb. delay (ns) | latency x area (norm. to V1) |"
echo "|---|---|---|---|---|---|"
base=""
for d in $(ls -d $ROOT/designs/v* | xargs -n1 basename); do
  lat=$(TAIL=6 $ROOT/tools/run_sim.sh designs/$d 20.7 100 2>&1 | grep LATENCY_NS | sed 's/.*avg=\([0-9.]*\) .*/\1/')
  syn=$($ROOT/tools/synth_design.sh designs/$d 2>&1)
  area=$(echo "$syn" | grep "Chip area" | sed 's/.*: //')
  ff=$(echo "$syn" | grep -E "DFF" | awk '{s+=$NF} END{print s}')
  dl=$(echo "$syn" | grep "Delay =" | sed 's/.*Delay = *\([0-9.]*\) ps.*/\1/')
  prod=$(python3 -c "print($lat*$area)")
  [ -z "$base" ] && base=$prod
  echo "| $d | $lat | $area | $ff | $(python3 -c "print(round($dl/1000,2))") | $(python3 -c "print(round($prod/$base,3))") |"
done
