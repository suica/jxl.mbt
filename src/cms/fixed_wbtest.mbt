///|
test "quick_saturate_word matches lcms2 rounding" {
  assert_eq(quick_saturate_word(-1.0), 0)
  assert_eq(quick_saturate_word(0.0), 0)
  assert_eq(quick_saturate_word(0.49), 0)
  assert_eq(quick_saturate_word(0.5), 1)
  assert_eq(quick_saturate_word(1234.4999), 1234)
  assert_eq(quick_saturate_word(65534.6), 65535)
  assert_eq(quick_saturate_word(1.0e9), 65535)
}

///|
test "fixed point helpers" {
  assert_eq(to_fixed_domain(0), 0)
  assert_eq(to_fixed_domain(0xFFFF), 0x10000)
  assert_eq(linear_interp(0x8000, 100, 200), 150)
  assert_eq(linear_interp(0x8000, 200, 100), 150)
  assert_eq(from_8_to_16(0xFF), 0xFFFF)
}

///|
test "reverse of a tabulated curve" {
  let c = ToneCurve::tabulated16([0, 0x4000, 0xFFFF])
  let r = c.reverse()
  let tmp = FixedArray::make(1, 0)
  assert_true((r.eval16(0x4000, tmp) - 0x8000).abs() <= 8)
  assert_eq(r.eval16(0, tmp), 0)
  assert_eq(r.eval16(0xFFFF, tmp), 0xFFFF)
}
