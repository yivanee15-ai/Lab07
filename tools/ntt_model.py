#!/usr/bin/env python3
"""Golden model of the Lab07 NTT (n=128, Q=12289), written straight from the spec."""
Q, Q0I, R = 12289, 12287, 1 << 16
N = 128


def modq_mul(a, b):
    """Montgomery multiplication exactly as in the spec pseudo-code."""
    x = a * b
    y = (x * Q0I) % R
    z = (x + y * Q) // R
    return z - Q if z >= Q else z


def brv7(k):
    return int(format(k, "07b")[::-1], 2)


def make_gmb(psi=None):
    """ASSUMED twiddle table (the real one is GMb.txt from the TA tar).
    GMb[k] = psi^brv7(k) * R mod Q  (Montgomery form), k = 1..127, GMb[0] unused."""
    if psi is None:
        psi = pow(11, (Q - 1) // 256, Q)  # 11 is a generator of Z_Q^*
    assert pow(psi, 128, Q) == Q - 1
    return [0] + [(pow(psi, brv7(k), Q) * R) % Q for k in range(1, N)]


def ntt_spec(x, gmb):
    """Literal transcription of NTT(x) from the spec."""
    x = list(x)
    t = 128
    m = 1
    while m < 128:
        ht = t // 2
        j1 = 0
        for i in range(m):
            s = gmb[m + i]
            j2 = j1 + ht
            for j in range(j1, j2):
                u = x[j]
                v = modq_mul(x[j + ht], s)
                x[j] = (u + v) % Q
                x[j + ht] = (u - v) % Q
            j1 += t
        t = ht
        m *= 2
    return x


def ntt_naive(x, psi=None):
    """Independent check: X[k] = P(psi^(2*brv7(k)+1)), P(X)=sum x_n X^n."""
    if psi is None:
        psi = pow(11, (Q - 1) // 256, Q)
    out = []
    for k in range(N):
        r = pow(psi, 2 * brv7(k) + 1, Q)
        out.append(sum(c * pow(r, n, Q) for n, c in enumerate(x)) % Q)
    return out


def front4_consts(gmb):
    """Field constants of the combined stage 1+2 (radix-4 on the raw 4-bit samples).
    y[32k+p] = x[p] + c1[k]*x[p+32] + c2[k]*x[p+64] + c3[k]*x[p+96]   (mod Q)"""
    f = lambda s: modq_mul(1, s)          # s * R^-1 mod Q  (field multiplier equivalent to modq_mul(., s))
    a1, a2, a3 = f(gmb[1]), f(gmb[2]), f(gmb[3])
    a12, a13 = a1 * a2 % Q, a1 * a3 % Q
    neg = lambda v: (Q - v) % Q
    c1 = [a2, neg(a2), a3, neg(a3)]
    c2 = [a1, a1, neg(a1), neg(a1)]
    c3 = [a12, neg(a12), neg(a13), a13]
    return c1, c2, c3


def front4(x, gmb):
    """first two stages computed with the radix-4 formula (self check of the idea)"""
    c1, c2, c3 = front4_consts(gmb)
    y = [0] * 128
    for k in range(4):
        for p in range(32):
            y[32 * k + p] = (x[p] + c1[k] * x[p + 32] + c2[k] * x[p + 64] + c3[k] * x[p + 96]) % Q
    return y


def two_stages(x, gmb):
    x = list(x)
    for m, ht in ((1, 64), (2, 32)):
        j1 = 0
        for i in range(m):
            s = gmb[m + i]
            for j in range(j1, j1 + ht):
                u = x[j]; v = modq_mul(x[j + ht], s)
                x[j] = (u + v) % Q; x[j + ht] = (u - v) % Q
            j1 += 2 * ht
    return x


def pack_words(x):
    """16 words of 32 bits, 8 x 4-bit coefs, lowest index in LSB."""
    return [sum(x[8 * w + i] << (4 * i) for i in range(8)) for w in range(16)]


if __name__ == "__main__":
    import random
    g = make_gmb()
    assert Q * Q0I % R == R - 1
    for _ in range(50):
        x = [random.randrange(16) for _ in range(N)]
        a, b = ntt_spec(x, g), ntt_naive(x)
        assert a == b, "spec algorithm != naive evaluation with assumed table"
    for _ in range(50):
        x = [random.randrange(16) for _ in range(N)]
        assert front4(x, g) == two_stages(x, g), "radix-4 front end formula mismatch"
    print("radix-4 front end (stage 1+2 as LUT sums) == two radix-2 stages")
    print("model OK: spec algorithm == naive polynomial evaluation (assumed GMb)")
