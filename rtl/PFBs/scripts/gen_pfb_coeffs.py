#!/usr/bin/env python3
"""Generate the coefficient ROM tables of rtl/PFBs/pfb_coeff_gen.sv.

casper_library's pfb_coeff_gen fills one ROM per tap a = 1 … TotalTaps
with pfb_coeff_gen_calc(PFBSize, TotalTaps, WindowType, n_inputs, nput,
fwidth, a):

    alltaps = TotalTaps · 2^PFBSize
    coeffs  = window(WindowType, alltaps) ·
              sinc(fwidth · ((0.5 : 1 : alltaps-0.5) / 2^PFBSize − TotalTaps/2))
    ROM a   = coeffs[(a-1)·2^PFBSize + 1 + nput : 2^n_inputs : a·2^PFBSize]
              (MATLAB 1-based; 2^(PFBSize-n_inputs) entries)

sinc(x) = sin(πx)/(πx). Each entry is stored as a CoeffBitWidth-bit signed
word with binary point CoeffBitWidth-1 (round half away from zero,
saturating: the same rule as the twiddle tables of this library), one hex
word per line, in COEFF_DIR/pfb_coeff_n<nput>_t<a>.mem.

Windows are computed as MATLAB's window(name, N) does with its default
parameters, in plain Python (no SciPy needed):

  rectwin, bartlett, triang, hamming, hann, blackman (symmetric, MATLAB's
  half-and-mirror evaluation), blackmanharris, nuttallwin, flattopwin,
  barthannwin, bohmanwin, parzenwin, gausswin (alpha 2.5), kaiser
  (beta 0.5), tukeywin (r 0.5)

Not supported (clear error): chebwin (Dolph–Chebyshev; not reproduced
bit-exactly here) and userwindow (a user-supplied function, not a
generated table). casper's mask spells the Bohman window "bohamwin"; both
spellings are accepted.

Usage:
  python3 rtl/PFBs/scripts/gen_pfb_coeffs.py --pfb-size 5 --total-taps 4 \\
          --window hamming --n-inputs 1 --nput 0 --fwidth 1 \\
          --coeff-bit-width 18 -o coeffs/
"""

import argparse
import math
from pathlib import Path


# ── windows (MATLAB definitions, symmetric) ─────────────────────────────────

def _mirror(half, n):
    """MATLAB's [w; w(end:-1:1)] (even n) or [w; w(end-1:-1:1)] (odd n)."""
    return half + half[::-1] if n % 2 == 0 else half + half[-2::-1]


def _gencoswin(kind, n):
    """MATLAB gencoswin (symmetric): evaluate the first half, then mirror."""
    if n == 1:
        return [1.0]
    m = n // 2 if n % 2 == 0 else (n + 1) // 2
    half = []
    for i in range(m):
        x = i / (n - 1)
        if kind == "hamming":
            v = 0.54 - 0.46 * math.cos(2 * math.pi * x)
        elif kind == "hann":
            v = 0.5 - 0.5 * math.cos(2 * math.pi * x)
        else:  # blackman
            v = 0.42 - 0.5 * math.cos(2 * math.pi * x) + 0.08 * math.cos(4 * math.pi * x)
        half.append(v)
    return _mirror(half, n)


def _cos_sum(a, n):
    """a0 − a1·cos(2πk/(n−1)) + a2·cos(4πk/(n−1)) − … over k = 0 … n−1."""
    if n == 1:
        return [1.0]
    return [sum((-1) ** i * c * math.cos(2 * math.pi * i * k / (n - 1)) for i, c in enumerate(a))
            for k in range(n)]


def _bessel_i0(x):
    s, term, k = 1.0, 1.0, 1
    while term > 1e-17 * s:
        term *= (x / (2 * k)) ** 2
        s += term
        k += 1
    return s


def window(name, n):
    name = {"bohamwin": "bohmanwin"}.get(name, name)
    if name == "rectwin":
        return [1.0] * n
    if name in ("hamming", "hann", "blackman"):
        return _gencoswin(name, n)
    if name == "blackmanharris":
        return _cos_sum([0.35875, 0.48829, 0.14128, 0.01168], n)
    if name == "nuttallwin":
        return _cos_sum([0.3635819, 0.4891775, 0.1365995, 0.0106411], n)
    if name == "flattopwin":
        return _cos_sum([0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368], n)
    if name == "bartlett":
        if n == 1:
            return [1.0]
        return [2 * k / (n - 1) if k <= (n - 1) / 2 else 2 - 2 * k / (n - 1) for k in range(n)]
    if name == "triang":
        if n % 2:
            half = [2 * k / (n + 1) for k in range(1, (n + 1) // 2 + 1)]
            return half + half[-2::-1]
        half = [(2 * k - 1) / n for k in range(1, n // 2 + 1)]
        return half + half[::-1]
    if name == "barthannwin":
        if n == 1:
            return [1.0]
        return [0.62 - 0.48 * abs(k / (n - 1) - 0.5) + 0.38 * math.cos(2 * math.pi * (k / (n - 1) - 0.5))
                for k in range(n)]
    if name == "bohmanwin":
        if n == 1:
            return [1.0]
        q = [abs(-1 + 2 * k / (n - 1)) for k in range(n)]
        w = [(1 - x) * math.cos(math.pi * x) + math.sin(math.pi * x) / math.pi for x in q]
        w[0] = w[-1] = 0.0
        return w
    if name == "parzenwin":
        out = []
        for i in range(n):
            k = abs(i - (n - 1) / 2)
            r = k / (n / 2)
            out.append(1 - 6 * r ** 2 + 6 * r ** 3 if k <= (n - 1) / 4 else 2 * (1 - r) ** 3)
        return out
    if name == "gausswin":
        if n == 1:
            return [1.0]
        alpha = 2.5
        return [math.exp(-0.5 * (alpha * (k - (n - 1) / 2) / ((n - 1) / 2)) ** 2) for k in range(n)]
    if name == "kaiser":
        beta = 0.5
        if n == 1:
            return [1.0]
        bes = _bessel_i0(beta)
        return [_bessel_i0(beta * math.sqrt(max(0.0, 1 - (2 * k / (n - 1) - 1) ** 2))) / bes
                for k in range(n)]
    if name == "tukeywin":
        r = 0.5
        if n == 1:
            return [1.0]
        per = r / 2
        tl = math.floor(per * (n - 1)) + 1
        th = n - tl + 1
        t = [k / (n - 1) for k in range(n)]
        return ([(1 + math.cos(math.pi / per * (t[k] - per))) / 2 for k in range(tl)]
                + [1.0] * (th - tl - 1)
                + [(1 + math.cos(math.pi / per * (t[k] - 1 + per))) / 2 for k in range(th - 1, n)])
    if name == "chebwin":
        raise ValueError("WindowType 'chebwin' is not supported: the Dolph-Chebyshev window "
                         "(MATLAB default 100 dB) is not reproduced bit-exactly here")
    if name == "userwindow":
        raise ValueError("WindowType 'userwindow' is not supported: it is a user-supplied "
                         "function, not a generated table")
    raise ValueError(f"unknown WindowType '{name}'")


SUPPORTED = ["bartlett", "barthannwin", "blackman", "blackmanharris", "bohamwin", "bohmanwin",
             "flattopwin", "gausswin", "hamming", "hann", "kaiser", "nuttallwin", "parzenwin",
             "rectwin", "triang", "tukeywin"]


# ── pfb_coeff_gen_calc ──────────────────────────────────────────────────────

def sinc(x):
    return 1.0 if x == 0 else math.sin(math.pi * x) / (math.pi * x)


def all_coeffs(pfb_size, total_taps, window_type, fwidth):
    alltaps = total_taps * 2 ** pfb_size
    w = window(window_type, alltaps)
    return [w[i] * sinc(fwidth * ((i + 0.5) / 2 ** pfb_size - total_taps / 2))
            for i in range(alltaps)]


def tap_coeffs(pfb_size, total_taps, window_type, n_inputs, nput, fwidth, a):
    """pfb_coeff_gen_calc(..., a): the real coefficients of ROM a (1-based)."""
    total = all_coeffs(pfb_size, total_taps, window_type, fwidth)
    cs = (a - 1) * 2 ** pfb_size + nput            # 0-based start
    ce = (a - 1) * 2 ** pfb_size + 2 ** pfb_size   # exclusive end
    return total[cs:ce:2 ** n_inputs]


def quantize_coeff(x, coeff_bit_width):
    """Real value -> signed integer, binary point coeff_bit_width-1 (round half away, saturate)."""
    scaled = x * 2 ** (coeff_bit_width - 1)
    q = math.floor(abs(scaled) + 0.5)
    q = q if scaled >= 0 else -q
    return min(max(q, -(1 << (coeff_bit_width - 1))), (1 << (coeff_bit_width - 1)) - 1)


def tap_table(pfb_size, total_taps, window_type, n_inputs, nput, fwidth, a, coeff_bit_width):
    """Raw (two's complement) words of ROM a."""
    return [quantize_coeff(c, coeff_bit_width) % (1 << coeff_bit_width)
            for c in tap_coeffs(pfb_size, total_taps, window_type, n_inputs, nput, fwidth, a)]


def mem_name(nput, a):
    return f"pfb_coeff_n{nput}_t{a}.mem"


def write_tables(out_dir, pfb_size, total_taps, window_type, n_inputs, nput, fwidth, coeff_bit_width):
    """Write the TotalTaps ROM files of one pfb_coeff_gen (input nput); returns their names."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    digits = (coeff_bit_width + 3) // 4
    names = []
    for a in range(1, total_taps + 1):
        rows = tap_table(pfb_size, total_taps, window_type, n_inputs, nput, fwidth, a, coeff_bit_width)
        (out_dir / mem_name(nput, a)).write_text("".join(f"{v:0{digits}x}\n" for v in rows))
        names.append(mem_name(nput, a))
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pfb-size", type=int, required=True, help="PFBSize")
    ap.add_argument("--total-taps", type=int, required=True, help="TotalTaps")
    ap.add_argument("--window", required=True, help="WindowType: " + ", ".join(SUPPORTED))
    ap.add_argument("--n-inputs", type=int, required=True, help="n_inputs (log2 of the inputs)")
    ap.add_argument("--nput", type=int, nargs="+", required=True,
                    help="input number(s) 0 … 2^n_inputs-1 (one table set each)")
    ap.add_argument("--fwidth", type=float, default=1.0, help="fwidth (default 1)")
    ap.add_argument("--coeff-bit-width", type=int, required=True, help="CoeffBitWidth")
    ap.add_argument("-o", "--output-dir", required=True)
    args = ap.parse_args()
    if not 0 <= args.n_inputs < args.pfb_size:
        ap.error("need 0 <= n_inputs < pfb-size")
    names = []
    try:
        for nput in args.nput:
            names += write_tables(args.output_dir, args.pfb_size, args.total_taps, args.window,
                                  args.n_inputs, nput, args.fwidth, args.coeff_bit_width)
    except ValueError as e:
        ap.error(str(e))
    print(f"wrote {len(names)} files to {args.output_dir}: {' '.join(names)}")


if __name__ == "__main__":
    main()
