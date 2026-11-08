#!/usr/bin/env python3
"""Generate input/golden pattern files for the Lab07 testbench.

pattern_in.dat : per pattern 16 lines, each a 32-bit word (8 hex digits)
pattern_out.dat: per pattern 128 lines, each a 16-bit value (4 hex digits)
GMb.txt        : ASSUMED twiddle table (replace with TA's file, then run gen_rom.py)
"""
import argparse, os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
from ntt_model import *


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "00_TESTBED"))
    ap.add_argument("--gmb", default=None, help="use this GMb.txt instead of the assumed table")
    a = ap.parse_args()
    random.seed(a.seed)
    if a.gmb:
        gmb = read_gmb(a.gmb)
    else:
        gmb = make_gmb()
        with open(os.path.join(a.out, "GMb.txt"), "w") as f:
            f.write("\n".join(str(v) for v in gmb) + "\n")
    pats = [[0] * 128, [15] * 128, [1] + [0] * 127, [0] * 127 + [15],
            [(i * 7 + 3) % 16 for i in range(128)], [i % 16 for i in range(128)]]
    for i in range(0, 128, 9):  # single impulses
        v = [0] * 128
        v[i] = random.randrange(1, 16)
        pats.append(v)
    while len(pats) < a.n:
        pats.append([random.randrange(16) for _ in range(128)])
    pats = pats[: a.n]
    with open(os.path.join(a.out, "pattern_in.dat"), "w") as fi, \
         open(os.path.join(a.out, "pattern_out.dat"), "w") as fo:
        for x in pats:
            for w in pack_words(x):
                fi.write("%08x\n" % w)
            for y in ntt_spec(x, gmb):
                fo.write("%04x\n" % y)
    print("wrote %d patterns to %s" % (len(pats), a.out))


def read_gmb(path):
    toks = open(path).read().split()
    vals = []
    for t in toks:
        t = t.lower()
        vals.append(int(t, 16) if t.startswith("0x") or any(c in "abcdef" for c in t) else int(t))
    if len(vals) == 127:
        vals = [0] + vals
    assert len(vals) == 128, "unexpected GMb.txt length %d" % len(vals)
    return vals


if __name__ == "__main__":
    main()
