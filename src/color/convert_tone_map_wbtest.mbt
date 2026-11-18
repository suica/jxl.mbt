///|
fn tone_map_test_samples() -> FixedArray[Float] {
  FixedArray::makei(10, idx => Float::from_int(idx / 5) * 0.1)
}

///|
fn tone_map_test_params() -> HdrParams {
  {
    luminances: [0.2126, 0.7152, 0.0722],
    intensity_target: 10000.0,
    min_nits: 0.0,
  }
}

///|
test "tone_map_range" {
  let r = tone_map_test_samples()
  let g = tone_map_test_samples()
  let b = tone_map_test_samples()
  tone_map(r, g, b, tone_map_test_params(), 255.0, false, 0, 10)
  for idx in 0..<10 {
    let expected = Float::from_int(idx / 5) * 0.8714331
    assert_true((r[idx] - expected).abs() < 2.0e-5)
    assert_true((g[idx] - expected).abs() < 2.0e-5)
    assert_true((b[idx] - expected).abs() < 2.0e-5)
  }
}

///|
test "tone_map_range_detect_peak" {
  let r = tone_map_test_samples()
  let g = tone_map_test_samples()
  let b = tone_map_test_samples()
  tone_map(r, g, b, tone_map_test_params(), 255.0, true, 0, 10)
  for idx in 0..<10 {
    let expected = Float::from_int(idx / 5)
    assert_true((r[idx] - expected).abs() < 2.0e-5)
    assert_true((g[idx] - expected).abs() < 2.0e-5)
    assert_true((b[idx] - expected).abs() < 2.0e-5)
  }
}

///|
test "tone_map_luma matches rgb" {
  let y = tone_map_test_samples()
  tone_map_luma(y, tone_map_test_params(), 255.0, false, 0, 10)
  for idx in 0..<10 {
    let expected = Float::from_int(idx / 5) * 0.8714331
    // Unlike the RGB path, black maps to a tiny positive value (PQ(0) > 0).
    assert_true((y[idx] - expected).abs() < 3.0e-5)
  }
}

///|
test "detect_peak" {
  let samples : FixedArray[Float] = [0.0, 0.05, 0.075, 0.1]
  let peak = detect_peak_luminance(
    samples,
    samples,
    samples,
    [0.2126, 0.7152, 0.0722],
    0,
    4,
  )
  assert_true((peak - 0.1).abs() < 1.0e-6)
}

///|
test "detect_peak_zero" {
  let samples : FixedArray[Float] = [0.0, 0.0]
  let peak = detect_peak_luminance(
    samples,
    samples,
    samples,
    [0.2126, 0.7152, 0.0722],
    0,
    2,
  )
  assert_eq(peak, 1.0)
}

///|
test "rec2408 eetf identity below knee" {
  // Samples below the knee point are not compressed.
  let it : Float = 1000.0
  let s = linear_to_pq_generic(0.01, it)
  let mapped = rec2408_eetf_generic(s, it, (0.0, 1000.0), (0.0, 1000.0))
  assert_true((mapped - s).abs() < 1.0e-6)
}
