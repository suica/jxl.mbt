# Writes small synthetic ICC profiles exercising the tag types the CMS reads.
import struct, math, os, sys
def s15(v): return struct.pack('>i', int(round(v * 65536)))
def xyz_tag(x, y, z): return b'XYZ ' + b'\0'*4 + s15(x) + s15(y) + s15(z)
def para(t, ps): return b'para' + b'\0'*4 + struct.pack('>HH', t, 0) + b''.join(s15(p) for p in ps)
def curv(vals): return b'curv' + b'\0'*4 + struct.pack('>I', len(vals)) + b''.join(struct.pack('>H', v) for v in vals)
def curv_gamma(g): return b'curv' + b'\0'*4 + struct.pack('>IH', 1, int(round(g*256)))
def pad4(b): return b + b'\0' * ((-len(b)) % 4)
def table(n, f): return [max(0, min(65535, int(round(f(i/(n-1)) * 65535)))) for i in range(n)]
def clut_values(grid, nin, nout, f):
    # first input most significant
    import itertools
    out = []
    for idx in itertools.product(*[range(g) for g in grid[:nin]]):
        x = [idx[k]/(grid[k]-1) for k in range(nin)]
        out.extend(f(x))
    return out
def q16(v): return max(0, min(65535, int(round(v*65535))))
def q8(v): return max(0, min(255, int(round(v*255))))
def mft2(nin, nout, grid, mat, intabs, f, outtabs):
    b = b'mft2' + b'\0'*4 + bytes([nin, nout, grid, 0]) + b''.join(s15(m) for m in mat)
    b += struct.pack('>HH', len(intabs[0]), len(outtabs[0]))
    for t in intabs: b += b''.join(struct.pack('>H', v) for v in t)
    b += b''.join(struct.pack('>H', q16(v)) for v in clut_values([grid]*nin, nin, nout, f))
    for t in outtabs: b += b''.join(struct.pack('>H', v) for v in t)
    return b
def mft1(nin, nout, grid, mat, inf, f, outf):
    b = b'mft1' + b'\0'*4 + bytes([nin, nout, grid, 0]) + b''.join(s15(m) for m in mat)
    for c in range(nin): b += bytes(q8(inf(c, i/255)) for i in range(256))
    b += bytes(q8(v) for v in clut_values([grid]*nin, nin, nout, f))
    for c in range(nout): b += bytes(q8(outf(c, i/255)) for i in range(256))
    return b
def lut_ab(sig, nin, nout, B=None, mat=None, M=None, clut=None, A=None):
    # sig b'mAB ' or b'mBA '; parts as lists of curve tag bytes / (grid, prec, f)
    hdr_len = 32
    body = b''; offs = {}
    def add(name, data):
        nonlocal body
        offs[name] = hdr_len + len(body); body += pad4(data)
    order = ['A', 'C', 'M', 'X', 'B'] if sig == b'mAB ' else ['B', 'X', 'M', 'C', 'A']
    for name in order:
        if name == 'A' and A: add('A', b''.join(pad4(c) for c in A))
        if name == 'B' and B: add('B', b''.join(pad4(c) for c in B))
        if name == 'M' and M: add('M', b''.join(pad4(c) for c in M))
        if name == 'X' and mat: add('X', b''.join(s15(v) for v in mat))
        if name == 'C' and clut:
            grid, prec, f = clut
            g16 = bytes(grid + [0]*(16-len(grid)))
            vals = clut_values(grid, nin, nout, f)
            data = g16 + bytes([prec, 0, 0, 0]) + (bytes(q8(v) for v in vals) if prec == 1 else b''.join(struct.pack('>H', q16(v)) for v in vals))
            add('C', data)
    o = lambda k: offs.get(k, 0)
    head = sig + b'\0'*4 + bytes([nin, nout, 0, 0]) + struct.pack('>5I', o('B'), o('X'), o('M'), o('C'), o('A'))
    return head + body
def profile(version, cls, cs, pcs, intent, tags):
    hdr = bytearray(128)
    struct.pack_into('>I', hdr, 8, version)
    hdr[12:16] = cls; hdr[16:20] = cs; hdr[20:24] = pcs
    hdr[36:40] = b'acsp'
    struct.pack_into('>I', hdr, 64, intent)
    hdr[68:80] = s15(0.9642) + s15(1.0) + s15(0.8249)
    n = len(tags); off = 128 + 4 + 12*n
    dirb = struct.pack('>I', n); data = b''; seen = {}
    for sig, d in tags:
        if id(d) in seen:
            o, l = seen[id(d)]
        else:
            o = off + len(data); l = len(d); data += pad4(d); seen[id(d)] = (o, l)
        dirb += sig + struct.pack('>II', o, l)
    out = bytearray(hdr + dirb + data)
    struct.pack_into('>I', out, 0, len(out))
    return bytes(out)

XYZN = 1 + 32767/32768
srgbm = [[0.4361, 0.3851, 0.1431], [0.2225, 0.7169, 0.0606], [0.0139, 0.0971, 0.7141]]
def rgb_to_xyz_enc(x):
    l = [v ** 2.2 for v in x]
    X = [sum(srgbm[i][j]*l[j] for j in range(3)) for i in range(3)]
    X[0] += 0.02*math.sin(3*x[1]); X[2] += 0.03*x[0]*x[1]
    return [max(0, v)/XYZN for v in X]
def xyz_to_rgb(x):
    X = [v*XYZN for v in x]
    inv = [[3.134, -1.617, -0.4906], [-0.9788, 1.916, 0.0335], [0.0719, -0.229, 1.405]]
    l = [sum(inv[i][j]*X[j] for j in range(3)) for i in range(3)]
    return [min(1, max(0, v)) ** (1/2.2) for v in l]
def lab_of(x):  # device -> normalized v4 Lab-ish
    return [0.05 + 0.9*(1 - 0.5*(x[0]+x[1]+x[2])/3), 0.5 + 0.3*(x[1]-x[0]), 0.5 + 0.25*(x[2]-x[1])]
def cmyk_to_lab(x):
    c, m, y, k = x
    L = (1-k)*(1 - 0.35*c - 0.45*m - 0.15*y) * 0.92 + 0.04
    return [L, 0.5 + 0.25*(m - c) - 0.05*y*k, 0.5 + 0.3*(y - 0.5*m) - 0.1*c]
def lab_to_cmyk(x):
    L, a, b = x
    k = max(0, 0.6 - L) ** 1.2
    return [min(1, max(0, v)) for v in [(1-L)*0.8 + (0.5-a)*0.5, (1-L)*0.7 + (a-0.5)*0.6, (1-L)*0.6 + (b-0.5)*0.7, k]]

ident = [1,0,0,0,1,0,0,0,1]
P = {}
# 1. v4 RGB with mAB/mBA (all elements), XYZ PCS
A2B = lut_ab(b'mAB ', 3, 3,
    A=[para(2, [2.1, 0.95, 0.05, 0.02]), para(3, [2.4, 1/1.055, 0.055/1.055, 1/12.92, 0.04045]), curv(table(64, lambda t: t**1.8))],
    clut=([5, 6, 7], 2, rgb_to_xyz_enc),
    M=[para(0, [1.1]), curv_gamma(0.9), curv([])],
    mat=[0.98, 0.01, 0.0, 0.02, 0.97, 0.01, 0.0, 0.03, 0.96, 0.001, -0.002, 0.003],
    B=[para(1, [1.0, 1.0, 0.0]), para(4, [1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0]), curv([0, 65535])])
B2A = lut_ab(b'mBA ', 3, 3,
    B=[para(0, [1.0]), curv([0, 65535]), para(0, [1.0])],
    mat=[1.01, -0.01, 0.0, 0.0, 1.0, 0.0, 0.01, 0.0, 0.99, 0.0, 0.001, -0.001],
    M=[curv(table(32, lambda t: t**0.95)), para(0, [1.05]), curv([])],
    clut=([9, 9, 9], 1, xyz_to_rgb),
    A=[para(4, [2.2, 0.98, 0.02, 0.9, 0.03, 0.01, 0.0]), curv(table(100, lambda t: t)), para(3, [2.4, 1/1.055, 0.055/1.055, 1/12.92, 0.04045])])
P['rgb_v4_lutab'] = profile(0x04300000, b'mntr', b'RGB ', b'XYZ ', 0,
    [(b'wtpt', xyz_tag(0.9642, 1.0, 0.8249)), (b'A2B0', A2B), (b'B2A0', B2A)])
# 2. v2 CMYK printer, Lab PCS, lut16 + lut8, media white not D50
wt = xyz_tag(0.86, 0.89, 0.72)
P['cmyk_v2_lut'] = profile(0x02100000, b'prtr', b'CMYK', b'Lab ', 1, [
    (b'wtpt', wt),
    (b'A2B0', mft2(4, 3, 5, ident, [table(64, lambda t: t**1.1) for _ in range(4)], lambda x: [v*65280/65535 for v in cmyk_to_lab(x)], [table(128, lambda t: t) for _ in range(3)])),
    (b'A2B1', mft1(4, 3, 5, ident, lambda c, t: t, lambda x: cmyk_to_lab(x), lambda c, t: t)),
    (b'B2A0', mft2(3, 4, 5, ident, [table(32, lambda t: t) for _ in range(3)], lambda x: lab_to_cmyk([v*65535/65280 for v in x]), [table(64, lambda t: t**0.9) for _ in range(4)])),
    (b'B2A1', mft1(3, 4, 7, ident, lambda c, t: t, lab_to_cmyk, lambda c, t: t)),
])
# 3. v2 RGB with lut16 (matrix) / lut8 (matrix), Lab PCS
mat = [0.9, 0.05, 0.05, 0.02, 0.95, 0.03, 0.01, 0.04, 0.95]
P['rgb_v2_lut_lab'] = profile(0x02200000, b'scnr', b'RGB ', b'Lab ', 0, [
    (b'wtpt', xyz_tag(0.9505, 1.0, 1.089)),
    (b'A2B0', mft2(3, 3, 9, mat, [table(40, lambda t: t**2.0) for _ in range(3)], lambda x: [v*65280/65535 for v in lab_of(x)], [table(40, lambda t: t) for _ in range(3)])),
    (b'B2A0', mft1(3, 3, 7, mat, lambda c, t: t, lambda x: [min(1, max(0, 1 - (x[0]-0.05)/0.9 + d)) for d in (0.3*(x[1]-0.5), 0, -0.25*(x[2]-0.5))], lambda c, t: t ** 0.5)),
])
# 4. v4 RGB matrix-shaper, mixed TRC types, D65 media white
P['rgb_v4_mixed_trc'] = profile(0x04200000, b'mntr', b'RGB ', b'XYZ ', 1, [
    (b'wtpt', xyz_tag(0.9505, 1.0, 1.089)),
    (b'rXYZ', xyz_tag(0.4361, 0.2225, 0.0139)), (b'gXYZ', xyz_tag(0.3851, 0.7169, 0.0971)), (b'bXYZ', xyz_tag(0.1431, 0.0606, 0.7141)),
    (b'rTRC', para(1, [2.2, 1.02, -0.02])), (b'gTRC', para(4, [2.3, 0.95, 0.05, 0.08, 0.05, 0.002, 0.001])), (b'bTRC', curv(table(512, lambda t: t**1.9))),
])
# 5. v4 gray, para type 2 TRC; v2 gray curv gamma
P['gray_v4_para'] = profile(0x04200000, b'mntr', b'GRAY', b'XYZ ', 0, [(b'wtpt', xyz_tag(0.9642, 1.0, 0.8249)), (b'kTRC', para(2, [2.0, 0.9, 0.1, 0.01]))])
P['gray_v2_gamma'] = profile(0x02100000, b'mntr', b'GRAY', b'XYZ ', 0, [(b'wtpt', xyz_tag(0.9505, 1.0, 1.089)), (b'kTRC', curv_gamma(1.8))])
# 6. 5-colour (5CLR) and 2-colour (2CLR) input profiles with mAB, Lab PCS
P['mch5_v4'] = profile(0x04300000, b'prtr', b'5CLR', b'Lab ', 0, [
    (b'wtpt', xyz_tag(0.9642, 1.0, 0.8249)),
    (b'A2B0', lut_ab(b'mAB ', 5, 3, A=[curv([])]*5, clut=([3, 4, 3, 3, 3], 2, lambda x: [0.95 - 0.15*sum(x), 0.5 + 0.2*(x[0]-x[1]) + 0.05*x[4], 0.5 + 0.2*(x[2]-x[3])]), B=[curv([])]*3)),
])
P['two_v4'] = profile(0x04300000, b'scnr', b'2CLR', b'Lab ', 0, [
    (b'wtpt', xyz_tag(0.9642, 1.0, 0.8249)),
    (b'A2B0', lut_ab(b'mAB ', 2, 3, A=[curv([]), para(0, [1.3])], clut=([9, 5], 2, lambda x: [0.95 - 0.4*x[0] - 0.3*x[1], 0.5 + 0.3*x[0]*x[1], 0.5 - 0.2*x[1]]), B=[curv([])]*3)),
])
P['gray_v4_clut'] = profile(0x04300000, b'scnr', b'GRAY', b'Lab ', 0, [
    (b'wtpt', xyz_tag(0.9642, 1.0, 0.8249)),
    (b'A2B0', lut_ab(b'mAB ', 1, 3, clut=([17], 2, lambda x: [x[0]**1.2, 0.5 + 0.02*math.sin(5*x[0]), 0.5]), B=[curv([])]*3)),
])
outdir = sys.argv[1]
for k, v in P.items():
    open(os.path.join(outdir, k + '.icc'), 'wb').write(v)
    print(k, len(v))
