#!/bin/bash
# Full functional regression:  tools/regress.sh [designs...]   (default: all designs/v*)
# every design x clk3 in {3.1, 4.1, 11.1, 20.7} x seeds (random clock phases) x 100 patterns
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DESIGNS=${@:-$(ls -d $ROOT/designs/v* | xargs -n1 basename)}
SEEDS=${SEEDS:-"0 1 2"}
NPAT=${NPAT:-100}
for d in $DESIGNS; do
  ok=1; lat=""
  for p in 3.1 4.1 11.1 20.7; do
    for sd in $SEEDS; do
      out=$(SIMARGS="+seed=$sd" TAIL=6 $ROOT/tools/run_sim.sh designs/$d $p $NPAT 2>&1)
      if ! echo "$out" | grep -q "PASSED"; then ok=0; echo "  FAIL $d clk3=$p seed=$sd"; echo "$out" | grep -E "ERR|FAIL" | head -3; fi
      if [ "$p" = "20.7" ] && [ -z "$lat" ]; then lat=$(echo "$out" | grep LATENCY_NS | sed 's/.*avg=\([0-9.]*\).*/\1/'); fi
    done
  done
  [ $ok = 1 ] && echo "$d : PASS  (avg latency @clk3=20.7ns = $lat clk3 cycles)" || echo "$d : FAIL"
done
