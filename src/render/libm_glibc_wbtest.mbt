// Reference hashes from glibc 2.35 (x86_64, FMA ifunc) and its hardware
// `fma`, produced by scratch C program libm_vectors.c:
// h = h * 1000003 + bits(result), NaN results hashed as the canonical NaN.

///|
fn libm_test_h(h : UInt64, v : UInt64) -> UInt64 {
  h * 1000003UL + v
}

///|
fn libm_test_cf(f : Float) -> UInt64 {
  (if f.is_nan() { 0x7fc00000U } else { f.reinterpret_as_uint() }).to_uint64()
}

///|
fn libm_test_cd(f : Double) -> UInt64 {
  if f.is_nan() {
    0x7ff8000000000000UL
  } else {
    f.reinterpret_as_uint64()
  }
}

///|
fn libm_cos_small_hash(step : UInt32) -> UInt64 {
  let end = (120.0 : Float).reinterpret_as_uint()
  let mut h = 0UL
  let mut u = 0U
  while u < end {
    h = libm_test_h(
      h,
      libm_test_cf(glibc_cosf(Float::reinterpret_from_uint(u))),
    )
    u = u + step
  }
  h
}

///|
fn libm_pow025_hash(step : UInt32) -> UInt64 {
  let mut h = 0UL
  let mut u = 0U
  while u < 0x7f800000U {
    h = libm_test_h(
      h,
      libm_test_cf(glibc_powf(Float::reinterpret_from_uint(u), 0.25)),
    )
    u = u + step
  }
  h
}

///|
test "glibc cosf matches glibc (sampled)" {
  assert_eq(libm_cos_small_hash(1009), 4636611405058631774UL)
  let mut h = 0UL
  let mut u = 0UL
  while u <= 0xffffffffUL {
    h = libm_test_h(
      h,
      libm_test_cf(glibc_cosf(Float::reinterpret_from_uint(u.to_uint()))),
    )
    u = u + 4099UL
  }
  assert_eq(h, 2313985927246417691UL)
}

///|
test "glibc powf matches glibc (sampled)" {
  assert_eq(libm_pow025_hash(1009), 12907836018166074050UL)
  let mut st = 1UL
  let mut h = 0UL
  for i in 0..<1000000 {
    st = st * 6364136223846793005UL + 1442695040888963407UL
    let r = st
    let mut x = Float::reinterpret_from_uint((r >> 32).to_uint())
    let mut y = Float::reinterpret_from_uint(r.to_uint())
    if i % 3 == 0 {
      y = Float::reinterpret_from_uint((r.to_uint() & 0x007fffff) | 0x3c000000)
    }
    if i % 5 == 0 {
      x = Float::reinterpret_from_uint(
        ((r >> 32).to_uint() & 0x00ffffff) | 0x3f000000,
      )
    }
    h = libm_test_h(h, libm_test_cf(glibc_powf(x, y)))
  }
  assert_eq(h, 6464561224565860958UL)
}

///|
test "software fma matches hardware fma" {
  let mut st = 2UL
  let next = fn() {
    st = st * 6364136223846793005UL + 1442695040888963407UL
    st
  }
  let mut h = 0UL
  for i in 0..<1000000 {
    let mut a = next()
    let mut b = next()
    let mut c = next()
    if i % 2 == 0 {
      a = (a & 0x800fffffffffffffUL) |
        ((1023UL + ((a >> 53) & 63UL) - 32UL) << 52)
      b = (b & 0x800fffffffffffffUL) |
        ((1023UL + ((b >> 53) & 63UL) - 32UL) << 52)
      c = (c & 0x800fffffffffffffUL) |
        ((1023UL + ((c >> 53) & 127UL) - 64UL) << 52)
    }
    h = libm_test_h(
      h,
      libm_test_cd(
        glibc_fma(
          a.reinterpret_as_double(),
          b.reinterpret_as_double(),
          c.reinterpret_as_double(),
        ),
      ),
    )
  }
  assert_eq(h, 3306999244878372372UL)
}

///|
/// Exhaustive comparison (about 3e9 calls); run on demand with
/// `JXL_LIBM_EXHAUSTIVE=1`-style manual invocation by renaming to a test.
fn libm_exhaustive_check() -> Bool {
  libm_cos_small_hash(1) == 8017989110737187168UL &&
  libm_pow025_hash(1) == 321035480743033772UL
}
