#!/usr/bin/env python3
"""Walk through the NTT of the spec on a degree-8 toy polynomial (same algorithm, n=8) and show the
real I/O packing for n=128.  Output is pasted into docs/spec_understanding.md."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from ntt_model import *

N8 = 8
psi8 = pow(11, (Q - 1) // (2 * N8), Q)         # primitive 16th root of unity
def brv(k, bits): return int(format(k, "0%db" % bits)[::-1], 2)
g8 = [0] + [(pow(psi8, brv(k, 3), Q) * R) % Q for k in range(1, N8)]

def ntt8(x, trace):
    x = list(x); t = N8; m = 1
    while m < N8:
        ht = t // 2; j1 = 0
        for i in range(m):
            s = g8[m + i]; j2 = j1 + ht
            for j in range(j1, j2):
                u = x[j]; v = modq_mul(x[j + ht], s)
                trace.append("  stage m=%d  GMb[%d]=%5d : x[%d]=%5d, x[%d]=%5d -> v=%5d -> x[%d]=(u+v)%%Q=%5d, x[%d]=(u-v)%%Q=%5d"
                             % (m, m + i, s, j, u, j + ht, x[j + ht], v, j, (u + v) % Q, j + ht, (u - v) % Q))
                x[j] = (u + v) % Q; x[j + ht] = (u - v) % Q
            j1 += t
        t = ht; m *= 2
    return x

x = [1, 2, 3, 4, 5, 6, 7, 8]
tr = []
y = ntt8(x, tr)
print("### toy example, n = 8, Q = 12289, input x =", x)
print("GMb (toy, index 1..7) =", g8[1:])
print("\n".join(tr))
print("output (x[0..7] after the last stage) =", y)
chk = [sum(c * pow(pow(psi8, 2 * brv(k, 3) + 1, Q), n, Q) for n, c in enumerate(x)) % Q for k in range(N8)]
print("independent check  X[k] = sum x[n] * psi^((2*brv(k)+1)*n) :", chk, "->", "OK" if chk == y else "MISMATCH")

print("\n### Montgomery product example (spec modq_mul), a=5, b=GMb[1] of the toy table =", g8[1])
a, b = 5, g8[1]
xx = a * b; yy = (xx * Q0I) % R; zz = (xx + yy * Q) // R
print("  x = a*b = %d ; y = (x*Q0I) mod 2^16 = %d ; z = (x + y*Q)/2^16 = %d ; z>=Q ? -> result %d" % (xx, yy, zz, modq_mul(a, b)))
print("  check: a*b*R^-1 mod Q =", a * b * pow(R, -1, Q) % Q)

print("\n### real packing, n = 128: coefficient i of the polynomial = 4 bit value x[i]")
xr = [i % 16 for i in range(128)]
w = pack_words(xr)
print("  x[i] = i mod 16 -> in_data per cycle:", ["%08x" % v for v in w[:4]], "...")
print("  (cycle 0: x0 in bits [3:0], x7 in bits [31:28])")
gm = make_gmb()
out = ntt_spec(xr, gm)
print("  out_data (128 cycles, 16 bit, value < 12289) first 8 :", out[:8])
