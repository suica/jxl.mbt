///|
/// The generic (non-SIMD) loop body of `linear_to_srgb`, used by upstream on
/// targets without SIMD support (kept here as a test reference).
fn linear_to_srgb_generic(s : Float) -> Float {
  let v = s.reinterpret_as_uint() & 0x7fff_ffffU
  let v_adj = Float::reinterpret_from_uint((v | 0x3e80_0000U) & 0x3eff_ffffU)
  let pow : Float = 0.059914046
  let pow = pow * v_adj - 0.10889456
  let pow = pow * v_adj + 0.107963754
  let pow = pow * v_adj + 0.018092343

  // `mul` won't be used when `v` is small.
  let idx = ((v >> 23) - 118U).reinterpret_as_int() & 0xf
  let mul = 0x4000_0000U |
    (srgb_powtable_upper[idx] << 18) |
    (srgb_powtable_lower[idx] << 10)
  let v = Float::reinterpret_from_uint(v)
  let small = v * 12.92
  let acc = pow * Float::reinterpret_from_uint(mul) - 0.055
  copysign_f32(if v <= 0.0031308 { small } else { acc }, s)
}

///|
fn ref_inputs() -> FixedArray[Float] {
  FixedArray::makei(inputs_bits.length(), i => {
    Float::reinterpret_from_uint(inputs_bits[i])
  })
}

///|
/// Asserts that `actual` matches the reference bit patterns exactly.
fn assert_bits(
  name : String,
  actual : FixedArray[Float],
  expected : FixedArray[UInt32],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<actual.length() {
    let a = actual[i].reinterpret_as_uint()
    if a != expected[i] {
      fail(
        "\{name}[\{i}]: got \{actual[i]} (\{a}), expected \{Float::reinterpret_from_uint(expected[i])} (\{expected[i]})",
      )
    }
  }
}

///|
test "mul_add_f32 is fused" {
  let r = mul_add_f32(0.1, 10.0, -1.0)
  assert_eq(r, 1.4901161e-8)
  assert_eq(mul_add_f32(2.0, 3.0, 1.0), 7.0)
  // halfway case of double rounding: 1 + 2^-24 + 2^-60
  let a : Float = Float::reinterpret_from_uint(0x3f800001U) // 1 + 2^-23
  let b : Float = Float::reinterpret_from_uint(0x3f000000U) // 0.5
  // a * b = 0.5 + 2^-24; + 0.5 = 1 + 2^-24 (tie, rounds to even = 1.0)
  assert_eq(mul_add_f32(a, b, 0.5), 1.0)
}

///|
test "mul_add_f64" {
  assert_eq(mul_add_f64(2.0, 3.0, 1.0), 7.0)
  let x = 0.1
  // 0.1 * 10 - 1 computed exactly
  assert_eq(mul_add_f64(x, 10.0, -1.0), 5.551115123125783e-17)
}

///|
test "fast_powf matches reference" {
  let inputs = ref_inputs()
  assert_bits(
    "powf045",
    inputs.map(x => fast_powf_generic(x.abs(), 0.45)),
    powf045_bits,
  )
  assert_bits(
    "powf24",
    inputs.map(x => fast_powf_generic(x.abs(), 2.4)),
    powf24_bits,
  )
}

///|
test "fast_powf accuracy" {
  for i in 1..<1000 {
    let x = Float::from_int(i) * 0.001
    let expected = @math.pow(x.to_double(), 2.4)
    let actual = fast_powf_generic(x, 2.4).to_double()
    assert_true((actual - expected).abs() <= expected * 1.0e-5 + 1.0e-9)
  }
}

///|
test "generic srgb matches reference" {
  assert_bits("l2srgb", ref_inputs().map(linear_to_srgb_generic), l2srgb_bits)
  let a = ref_inputs()
  srgb_to_linear(a)
  assert_bits("srgb2l", a, srgb2l_bits)
}

///|
test "srgb roundtrip" {
  let n = 1000
  let a = FixedArray::makei(n, i => Float::from_int(i) / Float::from_int(n))
  linear_to_srgb(a)
  srgb_to_linear(a)
  let mut max_err : Float = 0.0
  for i in 0..<n {
    let expected = Float::from_int(i) / Float::from_int(n)
    max_err = max_err.max((a[i] - expected).abs())
  }
  // Same as upstream: the round trip error peaks at ~1.78e-4.
  assert_true(max_err < 2.0e-4)
}

///|
test "generic bt709 matches reference" {
  assert_bits(
    "l2bt709",
    ref_inputs().map(linear_to_bt709_generic),
    l2bt709_bits,
  )
  let a = ref_inputs()
  bt709_to_linear(a)
  assert_bits("bt7092l", a, bt7092l_bits)
}

///|
test "generic pq matches reference" {
  assert_bits(
    "l2pq",
    ref_inputs().map(x => linear_to_pq_generic(x, 1000.0)),
    l2pq_bits,
  )
  assert_bits(
    "pq2l",
    ref_inputs().map(x => pq_to_linear_generic(x, 1000.0)),
    pq2l_bits,
  )
}

///|
const PQ_M1 : Double = 1305.0 / 8192.0

///|
const PQ_M2 : Double = 2523.0 / 32.0

///|
const PQ_C1 : Double = 107.0 / 128.0

///|
const PQ_C2 : Double = 2413.0 / 128.0

///|
const PQ_C3 : Double = 2392.0 / 128.0

///|
test "pq_inverse_eotf_100k" {
  let n = 100000
  let input = FixedArray::makei(n, idx => Float::from_int(idx) * 1.0e-5)
  linear_to_pq(input, 10000.0)
  for idx in 0..<n {
    let linear = (Float::from_int(idx) * 1.0e-5).to_double()
    let y_m1 = @math.pow(linear, PQ_M1)
    let expected = @math.pow(
      (y_m1 * PQ_C2 + PQ_C1) / (y_m1 * PQ_C3 + 1.0),
      PQ_M2,
    )
    let diff = (expected - input[idx].to_double()).abs()
    assert_true(diff < 1.0e-6)
  }
}

///|
test "pq_roundtrip_10k" {
  let n = 10000
  let input = FixedArray::makei(n, idx => Float::from_int(idx) * 1.0e-5)
  linear_to_pq(input, 10000.0)
  pq_to_linear(input, 1000.0)
  for idx in 0..<n {
    let expected = Float::from_int(idx) * 1.0e-4
    let diff = (expected - input[idx]).abs()
    assert_true(diff < 1.0e-5)
  }
}

///|
test "hlg roundtrip" {
  let n = 1000
  let a = FixedArray::makei(n, i => Float::from_int(i - 500) / 500.0)
  linear_to_hlg(a)
  // the signal at 1/12 is 0.5, at 1 it is ~1
  hlg_to_linear(a)
  for i in 0..<n {
    let expected = Float::from_int(i - 500) / 500.0
    assert_true((a[i] - expected).abs() < 1.0e-5)
  }
  let b : FixedArray[Float] = [1.0 / 12.0, 1.0]
  linear_to_hlg(b)
  assert_true((b[0] - 0.5).abs() < 1.0e-6)
  assert_true((b[1] - 1.0).abs() < 1.0e-5)
}

///|
test "hlg ootf roundtrip" {
  let lum : FixedArray[Float] = [0.2627, 0.678, 0.0593]
  let r : FixedArray[Float] = [0.1, 0.5, 0.9]
  let g : FixedArray[Float] = [0.2, 0.4, 0.8]
  let b : FixedArray[Float] = [0.3, 0.3, 0.7]
  hlg_oo(r, g, b, lum, 1000.0)
  hlg_inverse_oo(r, g, b, lum, 1000.0)
  assert_true((r[0] - 0.1).abs() < 1.0e-5)
  assert_true((g[1] - 0.4).abs() < 1.0e-5)
  assert_true((b[2] - 0.7).abs() < 1.0e-5)
  // 300 nits: no-op
  let r2 : FixedArray[Float] = [0.5]
  hlg_inverse_oo(r2, [0.5], [0.5], lum, 300.0)
  assert_eq(r2[0], 0.5)
}

///|
test "apply_gamma" {
  let a : FixedArray[Float] = [0.0, 1.0e-8, 0.25, 1.0]
  apply_gamma(a, 0.5)
  assert_eq(a[0], 0.0)
  assert_eq(a[1], 0.0)
  assert_true((a[2] - 0.5).abs() < 1.0e-5)
  assert_true((a[3] - 1.0).abs() < 1.0e-5)
  // sub-range only
  let b : FixedArray[Float] = [0.25, 0.25, 0.25]
  apply_gamma(b, 0.5, start=1, len=1)
  assert_eq(b[0], 0.25)
  assert_true((b[1] - 0.5).abs() < 1.0e-5)
  assert_eq(b[2], 0.25)
}

///|
test "pq and hlg tables" {
  let pq = pq_table(4096)
  assert_eq(pq.length(), 4096)
  assert_eq(pq[0], 0)
  assert_eq(pq[4095], 65535)
  let hlg = hlg_table(4096)
  assert_eq(hlg[0], 0)
  assert_true(hlg[4095] >= 65534)
  for i in 1..<4096 {
    assert_true(pq[i] >= pq[i - 1])
    assert_true(hlg[i] >= hlg[i - 1])
  }
}

///|
test "ycbcr matches reference" {
  let inputs = ref_inputs()
  let n = inputs.length()
  let out = FixedArray::make(n * 3, (0.0 : Float))
  for i in 0..<n {
    let cb : FixedArray[Float] = [inputs[i] * 0.5]
    let y : FixedArray[Float] = [inputs[(i * 7 + 3) % n] * 0.5]
    let cr : FixedArray[Float] = [inputs[(i * 5 + 1) % n] * 0.5]
    ycbcr_to_rgb(cb, y, cr)
    out[i * 3] = cb[0]
    out[i * 3 + 1] = y[0]
    out[i * 3 + 2] = cr[0]
  }
  assert_bits("ycbcr", out, ycbcr_bits)
}

///|
test "xyb matches reference" {
  let inputs = ref_inputs()
  let n = inputs.length()
  let out = FixedArray::make(n * 3, (0.0 : Float))
  let ob : FixedArray[Float] = [
    -0.0037930732552754493, -0.0037930732552754493, -0.0037930732552754493,
  ]
  for i in 0..<n {
    let x : FixedArray[Float] = [inputs[i] * 0.05]
    let y : FixedArray[Float] = [inputs[(i * 7 + 3) % n] * 0.5]
    let b : FixedArray[Float] = [inputs[(i * 5 + 1) % n] * 0.5]
    xyb_run(x, y, b, ob, 255.0)
    out[i * 3] = x[0]
    out[i * 3 + 1] = y[0]
    out[i * 3 + 2] = b[0]
  }
  assert_bits("xyb", out, xyb_bits)
}
