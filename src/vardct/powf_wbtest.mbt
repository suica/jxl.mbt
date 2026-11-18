///|
/// Hashes of `f32::powf` results computed by Rust (glibc 2.35, x86_64 with FMA)
/// for LCG-generated arguments; see `powf_hash`.
test "powf matches glibc bit-exactly" {
  let expected : FixedArray[UInt] = [1494689381U, 4156348878U, 613265149U]
  let state = { state: 12345U }
  for mode in 0..<3 {
    let mut h = 2166136261U
    for _ in 0..<200000 {
      let (x, y) = match mode {
        0 => {
          let a = Float::from_uint(state.next_raw() >> 8) / 16777216.0 * 8.0
          let f = Float::from_uint(state.next_raw() >> 8) / 16777216.0
          (a, f)
        }
        1 => {
          let x = Float::reinterpret_from_uint(state.next_raw())
          let y = Float::from_uint(state.next_raw() >> 8) / 16777216.0 * 40.0 -
            20.0
          (x, y)
        }
        _ => {
          let x = Float::reinterpret_from_uint(state.next_raw())
          let y = Float::reinterpret_from_uint(state.next_raw())
          (x, y)
        }
      }
      let r = powf(x, y)
      let b = if r.is_nan() { 0x7fc00000U } else { r.reinterpret_as_uint() }
      h = h ^ b
      h = h * 16777619U
    }
    assert_eq(h, expected[mode], msg="mode \{mode}")
  }
}

///|
test "powf special values" {
  assert_eq(powf(2.0, 10.0), 1024.0)
  assert_eq(powf(-2.0, 3.0), -8.0)
  assert_true(powf(-2.0, 0.5).is_nan())
  assert_eq(powf(0.0, -1.0), Float::reinterpret_from_uint(0x7f800000))
  assert_eq(powf(5.0, 0.0), 1.0)
  assert_eq(powf(1.0, Float::reinterpret_from_uint(0x7fc00000)), 1.0)
}
