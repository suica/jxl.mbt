// `cosf` as used by jxl-oxide through Rust's `f32::cos` (system libm). On
// x86_64 glibc 2.35 with FMA and AVX2 this is `__cosf_fma`: the Arm
// optimized-routines algorithm (sysdeps/ieee754/flt-32/s_cosf.c,
// s_sincosf.h, sincosf_poly.h) compiled with `-mfma -mavx2`, so every
// `a * b + c` is fused. Used by `sec_half` for DCT sizes >= 64.

///|
priv struct SincosTable {
  sign : FixedArray[Double]
  hpi_inv : Double
  hpi : Double
  c0 : Double
  c1 : Double
  c2 : Double
  c3 : Double
  c4 : Double
  s1 : Double
  s2 : Double
  s3 : Double
}

///|
/// The second entry computes -cos(x) rather than cos(x).
let sincosf_table : FixedArray[SincosTable] = [
  {
    sign: [1.0, -1.0, -1.0, 1.0],
    hpi_inv: d(0x41645F306DC9C883UL),
    hpi: d(0x3FF921FB54442D18UL),
    c0: 1.0,
    c1: d(0xBFDFFFFFFD0C621CUL),
    c2: d(0x3FA55553E1068F19UL),
    c3: d(0xBF56C087E89A359DUL),
    c4: d(0x3EF99343027BF8C3UL),
    s1: d(0xBFC555545995A603UL),
    s2: d(0x3F81107605230BC4UL),
    s3: d(0xBF2994EB3774CF24UL),
  },
  {
    sign: [1.0, -1.0, -1.0, 1.0],
    hpi_inv: d(0x41645F306DC9C883UL),
    hpi: d(0x3FF921FB54442D18UL),
    c0: -1.0,
    c1: -d(0xBFDFFFFFFD0C621CUL),
    c2: -d(0x3FA55553E1068F19UL),
    c3: -d(0xBF56C087E89A359DUL),
    c4: -d(0x3EF99343027BF8C3UL),
    s1: d(0xBFC555545995A603UL),
    s2: d(0x3F81107605230BC4UL),
    s3: d(0xBF2994EB3774CF24UL),
  },
]

///|
/// 4/PI to 192 bit precision.
let inv_pio4 : FixedArray[UInt32] = [
  0xa2, 0xa2f9, 0xa2f983, 0xa2f9836e, 0xf9836e4e, 0x836e4e44, 0x6e4e4415, 0x4e441529,
  0x441529fc, 0x1529fc27, 0x29fc2757, 0xfc2757d1, 0x2757d1f5, 0x57d1f534, 0xd1f534dd,
  0xf534ddc0, 0x34ddc0db, 0xddc0db62, 0xc0db6295, 0xdb629599, 0x6295993c, 0x95993c43,
  0x993c4390, 0x3c439041,
]

///|
/// 2PI * 2^-64.
let pi63 : Double = d(0x3C1921FB54442D18UL)

///|
fn abstop12(x : Float) -> UInt32 {
  (x.reinterpret_as_uint() >> 20) & 0x7ffU
}

///|
fn sinf_poly(x : Double, x2 : Double, p : SincosTable, n : Int32) -> Float {
  if (n & 1) == 0 {
    let x3 = x * x2
    let s1 = fma_f64(x2, p.s3, p.s2)
    let x7 = x3 * x2
    let s = fma_f64(x3, p.s1, x)
    Float::from_double(fma_f64(x7, s1, s))
  } else {
    let x4 = x2 * x2
    let c2 = fma_f64(x2, p.c4, p.c3)
    let c1 = fma_f64(x2, p.c1, p.c0)
    let x6 = x4 * x2
    let c = fma_f64(x4, p.c2, c1)
    Float::from_double(fma_f64(x6, c2, c))
  }
}

///|
/// Returns `(reduced x, quadrant)`.
fn reduce_fast(x : Double, p : SincosTable) -> (Double, Int32) {
  let r = x * p.hpi_inv
  let n = (r.to_int() + 0x800000) >> 24
  // `x - n * hpi`, contracted into a fused negative multiply-add.
  (fma_f64(-n.to_double(), p.hpi, x), n)
}

///|
fn reduce_large(xi : UInt32) -> (Double, Int32) {
  let base = ((xi >> 26) & 15U).reinterpret_as_int()
  let shift = ((xi >> 23) & 7U).reinterpret_as_int()
  let xi = ((xi & 0xffffffU) | 0x800000U) << shift
  let res0 = (xi * inv_pio4[base]).to_uint64()
  let res1 = xi.to_uint64() * inv_pio4[base + 4].to_uint64()
  let res2 = xi.to_uint64() * inv_pio4[base + 8].to_uint64()
  let res0 = (res2 >> 32) | (res0 << 32)
  let res0 = res0 + res1
  let n = (res0 + (1UL << 61)) >> 62
  let res0 = res0 - (n << 62)
  let x = res0.reinterpret_as_int64().to_double()
  (x * pi63, n.to_int())
}

///|
/// `cosf(y)`, bit-compatible with glibc's x86_64 FMA implementation.
fn cosf(y : Float) -> Float {
  let x = y.to_double()
  let pio4 = Float::reinterpret_from_uint(0x3f490fdbU)
  if abstop12(y) < abstop12(pio4) {
    let x2 = x * x
    if abstop12(y) < abstop12(Float::reinterpret_from_uint(0x39800000U)) {
      return 1.0
    }
    sinf_poly(x, x2, sincosf_table[0], 1)
  } else if abstop12(y) < abstop12(120.0) {
    let (x, n) = reduce_fast(x, sincosf_table[0])
    let s = sincosf_table[0].sign[n & 3]
    let p = if (n & 2) != 0 { sincosf_table[1] } else { sincosf_table[0] }
    sinf_poly(x * s, x * x, p, n ^ 1)
  } else if abstop12(y) < abstop12(Float::reinterpret_from_uint(0x7f800000U)) {
    let xi = y.reinterpret_as_uint()
    let sign = (xi >> 31).reinterpret_as_int()
    let (x, n) = reduce_large(xi)
    let s = sincosf_table[0].sign[(n + sign) & 3]
    let p = if ((n + sign) & 2) != 0 {
      sincosf_table[1]
    } else {
      sincosf_table[0]
    }
    sinf_poly(x * s, x * x, p, n ^ 1)
  } else {
    // __math_invalidf
    (y - y) / (y - y)
  }
}
