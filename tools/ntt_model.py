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
    print("model OK: spec algorithm == naive polynomial evaluation (assumed GMb)")
