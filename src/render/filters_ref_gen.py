# Reference values for render-filters tests, written from the jxl-oxide Rust code / spec formulas.
import numpy as np, math, sys
f32 = np.float32
M64 = (1 << 64) - 1

def bits(v):
    return int(np.array([v], dtype=np.float32).view(np.uint32)[0])

def hash_grid(rows):  # rows: list of lists of float32
    h = 0
    for row in rows:
        for v in row:
            h = (h * 1000003 + bits(v)) & M64
    return h

# ---------------- RNG ----------------
def split_mix_64(z):
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return z ^ (z >> 31)

class Rng:
    def __init__(self, seed0, seed1):
        self.s0 = [0] * 8; self.s1 = [0] * 8
        self.s0[0] = split_mix_64((seed0 + 0x9E3779B97F4A7C15) & M64)
        self.s1[0] = split_mix_64((seed1 + 0x9E3779B97F4A7C15) & M64)
        for i in range(1, 8):
            self.s0[i] = split_mix_64(self.s0[i - 1]); self.s1[i] = split_mix_64(self.s1[i - 1])
    def u32s(self):
        out = []
        for i in range(8):
            s1 = self.s0[i]; s0 = self.s1[i]
            ret = (s1 + s0) & M64
            self.s0[i] = s0
            s1 ^= (s1 << 23) & M64
            self.s1[i] = s1 ^ (s0 ^ (s1 >> 18) ^ (s0 >> 5))
            out += [ret & 0xffffffff, ret >> 32]
        return out

def tofloat(u):
    return np.array([(u >> 9) | 0x3f800000], dtype=np.uint32).view(np.float32)[0]

out = []
def emit(s): out.append(s)

r = Rng((3 << 32) + 1, (256 << 32) + 512)
a = r.u32s(); b = r.u32s()
emit("///|\nlet ref_rng_u32 : FixedArray[UInt] = [%s]\n" % ", ".join(str(v) for v in a + b))

# ---------------- noise ----------------
def mirror(o, n):
    while True:
        if o < 0: o = -(o + 1)
        elif o >= n: o = 2 * n - o - 1
        else: return o

def init_noise(vis, invis, W, H, gd):
    seed0 = (vis << 32) + invis
    full = [np.zeros((H, W), dtype=np.float32) for _ in range(3)]
    gpr = (W + gd - 1) // gd
    ng = gpr * ((H + gd - 1) // gd)
    for gi in range(ng):
        gx, gy = gi % gpr, gi // gpr
        x0, y0 = gx * gd, gy * gd
        rng = Rng(seed0, (x0 << 32) + y0)
        gw, gh = min(gd, W - x0), min(gd, H - y0)
        wn2 = (gw + 15) // 16; stride = wn2 * 16
        for c in range(3):
            vals = []
            for _ in range(wn2 * gh):
                vals += r_floats(rng)
            arr = np.array(vals, dtype=np.float32).reshape(gh, stride)
            full[c][y0:y0 + gh, x0:x0 + gw] = arr[:, :gw]
    conv = []
    ys = [mirror(y, H) for y in range(-2, H + 2)]
    xs = [mirror(x, W) for x in range(-2, W + 2)]
    for c in range(3):
        p = full[c][np.ix_(ys, xs)]
        # jxl-oxide sums the 5 rows in the order of its ring buffer: slot dy
        # holds the row o (-2..2) away with (y_in_group + o + 2) % 5 == dy.
        s = np.zeros((H, W), dtype=np.float32)
        for y in range(H):
            yg = y % gd
            for dy in range(5):
                o = (dy - yg - 2) % 5
                if o > 2: o -= 5
                for dx in range(5):
                    s[y] = s[y] + p[y + 2 + o, dx:dx + W] * f32(0.16)
        conv.append(s - p[2:2 + H, 2:2 + W] * f32(4.0))
    return conv

def r_floats(rng):
    return [tofloat(u) for u in rng.u32s()]

NW, NH, GD = 257, 130, 128
conv = init_noise(2, 1, NW, NH, GD)
for c in range(3):
    emit("///|\nlet ref_noise_conv_hash_%d : UInt64 = %dUL\n" % (c, hash_grid(conv[c])))

# render_noise: image region left=5, top=3, 40x30
def img_val(x, y, c):
    return f32((x * 7 + y * 13 + c * 29) % 61) / f32(64)
L, T, RW, RH = 5, 3, 40, 30
lut = [f32(v) for v in [0.0, 0.05, 0.1, 0.4, 0.2, 0.3, 0.6, 0.25]]
lut9 = lut + [lut[7]]
corr_x, corr_b = f32(0.125), f32(0.875)
g = [[[img_val(x, y, c) for x in range(RW)] for y in range(RH)] for c in range(3)]
for fy in range(RH):
    for fx in range(RW):
        x, y = fx + L, fy + T
        gx, gy = g[0][fy][fx], g[1][fy][fx]
        nxv, nyv, nbv = conv[0][y][x], conv[1][y][x], conv[2][y][x]
        in_x = gx + gy; in_y = gy - gx
        sx_ = max(f32(0), in_x * f32(3)); sy_ = max(f32(0), in_y * f32(3))
        xi = min(int(sx_), 7); yi = min(int(sy_), 7)
        xf = sx_ - f32(xi); yf = sy_ - f32(yi)
        sx = (lut9[xi + 1] - lut9[xi]) * xf + lut9[xi]
        sy = (lut9[yi + 1] - lut9[yi]) * yf + lut9[yi]
        nx = f32(0.22) * sx * (f32(0.0078125) * nxv + f32(0.9921875) * nbv)
        ny = f32(0.22) * sy * (f32(0.0078125) * nyv + f32(0.9921875) * nbv)
        g[0][fy][fx] = gx + (corr_x * (nx + ny) + nx - ny)
        g[1][fy][fx] = gy + (nx + ny)
        g[2][fy][fx] = g[2][fy][fx] + corr_b * (nx + ny)
for c in range(3):
    emit("///|\nlet ref_noise_render_hash_%d : UInt64 = %dUL\n" % (c, hash_grid(g[c])))

# ---------------- EPF ----------------
EW, EH, EL, ET = 21, 19, 8, 16
def epf_in(x, y, c):
    return f32((x * x + 3 * y + 7 * c) % 13) / f32(4096)
def sigma_val(bx, by):
    return f32((bx * 3 + by * 5) % 7) * f32(0.1) + f32(0.25)
scale = [f32(40.0), f32(5.0), f32(3.5)]
p0, p2, bsm = f32(0.9), f32(6.5), f32(2.0) / f32(3.0)
K1 = [(0, -1), (0, 1), (-1, 0), (1, 0)]
K2 = [(0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)]
D = {0: [(0, -1), (1, 0), (0, 0), (-1, 0), (0, 1)], 1: [(0, -1), (0, 0), (0, 1), (-1, 0), (1, 0)], 2: [(0, 0)]}
NEG = f32(6.6) * (f32(0.70710677) - f32(1.0))

def epf_pass(img, step, use_sigma_grid):
    kern = K2 if step == 0 else K1
    dist = D[step]
    stepm = p0 if step == 0 else (p2 if step == 2 else f32(1.0))
    out = [[[f32(0)] * EW for _ in range(EH)] for _ in range(3)]
    for y in range(EH):
        iy_img = y + ET
        for x in range(EW):
            ix_img = x + EL
            s = sigma_val(ix_img // 8, iy_img // 8) if use_sigma_grid else f32(1.0)
            if s < f32(0.3):
                for c in range(3): out[c][y][x] = img[c][y][x]
                continue
            border = (ix_img % 8 in (0, 7)) or (iy_img % 8 in (0, 7))
            sm = stepm * bsm if border else stepm
            sw = f32(1.0)
            sums = [img[c][y][x] for c in range(3)]
            for (kx, ky) in kern:
                d = f32(0)
                for c in range(3):
                    acc = f32(0)
                    for (ix, iy) in dist:
                        acc = acc + abs(img[c][mirror(y + ky + iy, EH)][mirror(x + kx + ix, EW)] - img[c][mirror(y + iy, EH)][mirror(x + ix, EW)])
                    d = d + scale[c] * acc
                w = max(f32(1.0) + d * (NEG / s * sm), f32(0))
                sw = sw + w
                for c in range(3):
                    sums[c] = sums[c] + w * img[c][mirror(y + ky, EH)][mirror(x + kx, EW)]
            for c in range(3): out[c][y][x] = sums[c] / sw
    return out

for use_grid in (True, False):
    for iters in (1, 2, 3):
        img = [[[epf_in(x, y, c) for x in range(EW)] for y in range(EH)] for c in range(3)]
        if iters == 3: img = epf_pass(img, 0, use_grid)
        img = epf_pass(img, 1, use_grid)
        if iters >= 2: img = epf_pass(img, 2, use_grid)
        tag = "grid" if use_grid else "modular"
        emit("///|\nlet ref_epf_%s_%d : FixedArray[UInt64] = [%s]\n" % (tag, iters, ", ".join("%dUL" % hash_grid(img[c]) for c in range(3))))

sys.stdout.write("// Generated by filters_ref_gen.py from formulas of the jxl-oxide Rust code. Do not edit.\n\n" + "\n".join(out))
