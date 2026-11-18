// Tests of the pxfm port against fixtures generated from pxfm 0.1.30.

///|
/// Evaluates a fixture/fuzz variant; f32 values travel in the low 32 bits.
fn eval_variant(name : String, a : UInt64, b : UInt64) -> UInt64 {
  let fa = fb(a)
  let fbv = fb(b)
  let ga = fbf(a.to_uint())
  let gb = fbf(b.to_uint())
  match name {
    "exp" => tb(f_exp(fa))
    "exp_generic" => tb(exp_gen(fa, false))
    "exp10" => tb(f_exp10(fa))
    "exp10_generic" => tb(exp10_gen(fa, false))
    "exp2" => tb(f_exp2(fa))
    "exp2_generic" => tb(exp2_gen(fa, false))
    "log" => tb(f_log(fa))
    "log10" => tb(f_log10(fa))
    "pow" => tb(f_pow(fa, fbv))
    "pow_generic" => tb(pow_impl(fa, fbv, false))
    "powf" => tbf(f_powf(ga, gb)).to_uint64()
    "powf_generic" => tbf(powf_gen(ga, gb, false)).to_uint64()
    "dirty_powf" => tbf(dirty_powf(ga, gb)).to_uint64()
    "cbrtf" => tbf(f_cbrtf(ga)).to_uint64()
    "cbrtf_generic" => tbf(cbrtf_gen(ga, false)).to_uint64()
    _ => abort("unknown variant " + name)
  }
}

///|
fn parse_hex(s : StringView) -> UInt64 {
  let mut v = 0UL
  for c in s {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      abort("bad hex")
    }
    v = (v << 4) | d.to_uint64()
  }
  v
}

///|
test "pxfm fixtures are bit-exact" {
  let mut total = 0
  let failures = []
  for entry in fixtures {
    let (name, data) = entry
    let mut n = 0
    for line in data.split("\n") {
      if line.is_empty() {
        continue
      }
      let f = line.split(" ").collect()
      let (a, b, want) = if f.length() == 2 {
        (parse_hex(f[0]), 0UL, parse_hex(f[1]))
      } else {
        (parse_hex(f[0]), parse_hex(f[1]), parse_hex(f[2]))
      }
      let got = eval_variant(name, a, b)
      if got != want && failures.length() < 40 {
        failures.push("\{name} \{line} got \{got.to_string(radix=16)}")
      }
      n += 1
    }
    total += n
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
  println("fixtures checked: \{total}")
  assert_true(total > 10000)
}

///|
test "upstream unit tests" {
  // pow.rs
  assert_eq(f_pow(1.0, inf_f64), 1.0)
  assert_eq(f_pow(2.0, inf_f64), inf_f64)
  assert_eq(f_pow(inf_f64, -0.5), 0.0)
  assert_eq(f_pow(2.1, 2.7), 7.412967494768546)
  assert_eq(f_pow(27.0, 1.0 / 3.0), 3.0)
  assert_eq(f_pow(fb(0x3cc0_0000_0000_0000UL), 102.0), 0.0)
  assert_eq(f_pow(3.0, 3.0), 27.0)
  assert_eq(f_pow(3.0, -3.0), 1.0 / 27.0)
  assert_eq(f_pow(3.0, 102.0), 4.638397686588102e48)
  // exp.rs
  assert_eq(f_exp(0.000000014901161193847656), 1.0000000149011614)
  assert_eq(f_exp(0.0), 1.0)
  assert_eq(f_exp(5.0), 148.4131591025766034211155800405522796)
  assert_eq(f_exp(inf_f64), inf_f64)
  assert_eq(f_exp(-inf_f64), 0.0)
  assert_true(is_nan(f_exp(nan_f64)))
  // exp10.rs
  assert_eq(f_exp10(-3.370739843267434), 0.00042585343701025656)
  assert_eq(f_exp10(1.0), 10.0)
  assert_eq(f_exp10(7.0), 10000000.0)
  // exp2.rs
  assert_eq(f_exp2(0.35), 1.2745606273192622)
  assert_eq(f_exp2(-0.6), 0.6597539553864471)
  // log.rs
  assert_eq(f_log(1.99999999779061), 0.693147179455250308807056)
  assert_eq(f_log(0.9999999999999999), -1.1102230246251565e-16)
  assert_eq(
    f_log(23.0),
    3.13549421592914969080675283181019611844238031484043574199863537748299324598,
  )
  assert_eq(f_log(fb(0x3ff1211bef8f68e9UL)), 0.06820362355801819)
  assert_eq(f_log(fb(0x3fe5556123e8a2b0UL)), -0.4054566631657151)
  assert_eq(f_log(0.0), -inf_f64)
  assert_true(is_nan(f_log(-1.0)))
  assert_eq(f_log(inf_f64), inf_f64)
  // powf.rs
  assert_eq(f_powf(0.5, 1.5432), 0.34312353)
  assert_eq(f_powf(nan_f32, 0.0), 1.0)
  assert_eq(f_powf(1.0, nan_f32), 1.0)
  // cbrtf.rs
  assert_eq(f_cbrtf(-27.0), -3.0)
  assert_eq(f_cbrtf(64.0), 4.0)
  assert_eq(f_cbrtf(-inf_f32), -inf_f32)
  // pow_exec.rs
  assert_eq(
    exp_dyadic(DyadicFloat128::new_from_f64(2.5)).fast_as_f64(),
    12.182493960703473,
  )
}

///|
test "fma emulation" {
  // exact cases and a few rounding-sensitive ones
  assert_eq(fma_f64(2.0, 3.0, 1.0), 7.0)
  let a = 1.0 + fb(0x3cb0000000000000UL) // 1 + 2^-52
  // (1 + 2^-52)^2 - 1 = 2^-51 + 2^-104
  assert_eq(
    fma_f64(a, a, -1.0),
    fb(0x3cc0000000000000UL) + fb(0x3970000000000000UL),
  )
  assert_eq(fma_f64(fb(0x7fefffffffffffffUL), 2.0, -inf_f64), -inf_f64)
  assert_eq(fmaf_f32(3.0, 5.0, -1.0), 14.0)
}
