// Port of moxcms 0.9.0 `trc.rs` for the `f32` pixel type
// (`PointeeSizeExpressible::FINITE == false`, linear tables of
// `NOT_FINITE_LINEAR_TABLE_SIZE = 16384` entries).

///|
const NOT_FINITE_LINEAR_TABLE_SIZE : Int32 = 16384

///|
pub(all) enum ToneReprCurve {
  /// `Lut(Vec<u16>)`
  Lut(FixedArray[Int32])
  Parametric(FixedArray[Float])
}

///|
fn ToneReprCurve::same(self : ToneReprCurve, other : ToneReprCurve) -> Bool {
  match (self, other) {
    (Lut(a), Lut(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if a[i] != b[i] {
          return false
        }
      }
      true
    }
    (Parametric(a), Parametric(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        // `f32` PartialEq
        if !(a[i] == b[i]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
#derive(Debug)
pub(all) struct ParametricCurve {
  g : Float
  a : Float
  b : Float
  c : Float
  d : Float
  e : Float
  f : Float
}

///|
pub fn ParametricCurve::new(params : FixedArray[Float]) -> ParametricCurve? {
  let g = params[0]
  match params.length() - 1 {
    0 => Some({ g, a: 1.0, b: 0.0, c: 0.0, d: 0.0, e: 0.0, f: 0.0, })
    2 => {
      let a = params[1]
      let b = params[2]
      Some({ g, a, b, c: 0.0, d: -b / a, e: 0.0, f: 0.0, })
    }
    3 => {
      let a = params[1]
      let b = params[2]
      let c = params[3]
      Some({ g, a, b, c: 0.0, d: -b / a, e: c, f: c, })
    }
    4 =>
      Some({
        g,
        a: params[1],
        b: params[2],
        c: params[3],
        d: params[4],
        e: 0.0,
        f: 0.0,
      })
    6 =>
      Some({
        g,
        a: params[1],
        b: params[2],
        c: params[3],
        d: params[4],
        e: params[5],
        f: params[6],
      })
    _ => None
  }
}

///|
fn ParametricCurve::is_linear(self : ParametricCurve) -> Bool {
  fabs(self.g - 1.0) < 1.0e-5 &&
  fabs(self.a - 1.0) < 1.0e-5 &&
  fabs(self.b) < 1.0e-5 &&
  fabs(self.c) < 1.0e-5
}

///|
pub fn ParametricCurve::eval(self : ParametricCurve, x : Float) -> Float {
  if x < self.d {
    self.c * x + self.f
  } else {
    @pxfm.f_powf(self.a * x + self.b, self.g) + self.e
  }
}

///|
pub fn ParametricCurve::invert(self : ParametricCurve) -> ParametricCurve? {
  // First check if the function is continuous at the cross-over point d.
  let d1 = @pxfm.f_powf(self.a * self.d + self.b, self.g) + self.e
  let d2 = self.c * self.d + self.f
  if fabs(d1 - d2) > 0.1 {
    return None
  }
  let d = d1
  let a = (1.0 : Float) / @pxfm.f_powf(self.a, self.g)
  let b = -self.e / @pxfm.f_powf(self.a, self.g)
  let g = (1.0 : Float) / self.g
  let e = -self.b / self.a
  let (c, f) = if d <= 0.0 {
    ((1.0 : Float), (0.0 : Float))
  } else {
    ((1.0 : Float) / self.c, -self.f / self.c)
  }
  if !(is_finite(g) &&
    is_finite(a) &&
    is_finite(b) &&
    is_finite(c) &&
    is_finite(d) &&
    is_finite(e) &&
    is_finite(f)) {
    return None
  }
  Some({ g, a, b, c, d, e, f, })
}

///|
fn is_finite(x : Float) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn u8_fixed_8number_to_float(x : Int32) -> Float {
  Float::from_double(x.to_double() / 256.0)
}

///|
fn passthrough_table(n : Int32) -> FixedArray[Float] {
  let max_value = NOT_FINITE_LINEAR_TABLE_SIZE - 1
  let cap_values = NOT_FINITE_LINEAR_TABLE_SIZE
  guard cap_values <= n else { abort("Invalid lut table construction") }
  let output = FixedArray::make(n, (0.0 : Float))
  let scale_value = 1.0 / max_value.to_double()
  for i in 0..<cap_values {
    output[i] = Float::from_double(i.to_double() * scale_value)
  }
  output
}

///|
fn linear_forward_table(n : Int32, gamma : Int32) -> FixedArray[Float] {
  let max_value = NOT_FINITE_LINEAR_TABLE_SIZE - 1
  let cap_values = NOT_FINITE_LINEAR_TABLE_SIZE
  guard cap_values <= n else { abort("Invalid lut table construction") }
  let output = FixedArray::make(n, (0.0 : Float))
  let g = u8_fixed_8number_to_float(gamma).to_double()
  let scale_value = 1.0 / max_value.to_double()
  for i in 0..<cap_values {
    output[i] = Float::from_double(@pxfm.f_pow(i.to_double() * scale_value, g))
  }
  output
}

///|
fn lut_interp_linear_float(x : Float, table : FixedArray[Float]) -> Float {
  let value = fmax(fmin(x, 1.0), 0.0) * Float::from_int(table.length() - 1)
  let upper = f2i(fceil(value))
  let lower = f2i(ffloor(value))
  let diff = Float::from_int(upper) - value
  let tu = table[upper]
  // mlaf(neg_mlaf(tu, tu, diff), table[lower], diff)
  tu + tu * -diff + table[lower] * diff
}

///|
fn lut_interp_linear(input_value : Double, table : FixedArray[Int32]) -> Float {
  let mut input_value = input_value
  if table.length() == 0 {
    return Float::from_double(input_value)
  }
  input_value *= (table.length() - 1).to_double()
  let upper = d2i(input_value.ceil())
  let lower = d2i(input_value.floor())
  let last = table.length() - 1
  let w0 = table[usize_min(upper, last)].to_double()
  let w1 = 1.0 - (upper.to_double() - input_value)
  let w2 = table[usize_min(lower, last)].to_double()
  let w3 = upper.to_double() - input_value
  let value = Float::from_double(w2 * w3 + w0 * w1)
  value * ((1.0 : Float) / (65535.0 : Float))
}

///|
/// `(i as usize).min(n)` for a non-negative `n` (negative `i` wraps to a huge
/// usize upstream, so it saturates to `n`).
fn usize_min(i : Int32, n : Int32) -> Int32 {
  if i < 0 || i > n {
    n
  } else {
    i
  }
}

///|
fn linear_lut_interpolate(
  n : Int32,
  table : FixedArray[Int32],
) -> FixedArray[Float] {
  let max_value = NOT_FINITE_LINEAR_TABLE_SIZE - 1
  let cap_values = NOT_FINITE_LINEAR_TABLE_SIZE
  guard cap_values <= n else { abort("Invalid lut table construction") }
  let output = FixedArray::make(n, (0.0 : Float))
  let scale_value = 1.0 / max_value.to_double()
  for i in 0..<cap_values {
    output[i] = lut_interp_linear(i.to_double() * scale_value, table)
  }
  output
}

///|
fn linear_curve_parametric(
  n : Int32,
  params : FixedArray[Float],
) -> FixedArray[Float]? {
  guard ParametricCurve::new(params) is Some(params) else { return None }
  let max_value = NOT_FINITE_LINEAR_TABLE_SIZE - 1
  let cap_value = NOT_FINITE_LINEAR_TABLE_SIZE
  let output = FixedArray::make(n, (0.0 : Float))
  let scale_value = (1.0 : Float) / Float::from_int(max_value)
  for i in 0..<cap_value.min(n) {
    output[i] = fclamp(params.eval(Float::from_int(i) * scale_value), 0.0, 1.0)
  }
  Some(output)
}

///|
fn linear_curve_parametric_s(
  n : Int32,
  params : FixedArray[Float],
) -> FixedArray[Float]? {
  guard ParametricCurve::new(params) is Some(params) else { return None }
  let output = FixedArray::make(n, (0.0 : Float))
  let scale_value = (1.0 : Float) / Float::from_int(n - 1)
  for i in 0..<n {
    output[i] = fclamp(params.eval(Float::from_int(i) * scale_value), 0.0, 1.0)
  }
  Some(output)
}

///|
/// `make_gamma_linear_table::<f32, BUCKET, N>`.
fn make_gamma_linear_table(bucket : Int32, n : Int32) -> FixedArray[Float] {
  let max_range = Float::from_double(1.0 / (n - 1).to_double())
  let table = FixedArray::make(bucket, (0.0 : Float))
  for v in 0..<n.min(bucket) {
    table[v] = Float::from_int(v) * max_range
  }
  table
}

///|
/// `lut_interp_linear_gamma_impl_f32::<f32, N, BIT_DEPTH>`.
fn lut_interp_linear_gamma_impl_f32(
  n : Int32,
  input_value : UInt32,
  table : FixedArray[Int32],
) -> Float {
  let guess : UInt32 = input_value * (table.length() - 1).reinterpret_as_uint()
  let cap_value = (n - 1).reinterpret_as_uint()
  let upper = (guess + cap_value - 1) / cap_value
  let lower = guess / cap_value
  let interp = guess % cap_value
  let lw_value = table[lower.reinterpret_as_int()]
  let hw_value = table[upper.reinterpret_as_int()]
  let mut value = Float::from_int(hw_value) * Float::from_uint(interp) +
    Float::from_int(lw_value) *
    (Float::from_int(n - 1) - Float::from_uint(interp))
  let max_colors = 1
  value = value /
    Float::from_int64((n - 1).to_int64() * 65535L / max_colors.to_int64())
  value
}

///|
fn make_gamma_lut(
  bucket : Int32,
  n : Int32,
  table : FixedArray[Int32],
) -> FixedArray[Float] {
  let new_table = FixedArray::make(bucket, (0.0 : Float))
  for v in 0..<n.min(bucket) {
    new_table[v] = lut_interp_linear_gamma_impl_f32(
      n,
      v.reinterpret_as_uint(),
      table,
    )
  }
  new_table
}

///|
fn lut_interp_linear16(input_value : Int32, table : FixedArray[Int32]) -> Int32 {
  let mut value : UInt32 = input_value.reinterpret_as_uint() *
    (table.length().reinterpret_as_uint() - 1U)
  let upper = ((value + 65534U) / 65535U).reinterpret_as_int() & 0xFFFF
  let lower = (value / 65535U).reinterpret_as_int() & 0xFFFF
  let interp : UInt32 = value % 65535U
  value = (
      table[upper].reinterpret_as_uint() * interp +
      table[lower].reinterpret_as_uint() * (65535U - interp)
    ) /
    65535U
  value.reinterpret_as_int() & 0xFFFF
}

///|
fn make_gamma_pow_table(
  bucket : Int32,
  n : Int32,
  gamma : Float,
  bit_depth : Int32,
) -> FixedArray[Float] {
  let table = FixedArray::make(bucket, (0.0 : Float))
  let cap = Float::from_int((1 << bit_depth) - 1)
  let scale = (1.0 : Float) / Float::from_int(n - 1)
  for v in 0..<n.min(bucket) {
    table[v] = cap * @pxfm.f_powf(Float::from_int(v) * scale, gamma)
  }
  table
}

///|
fn make_gamma_parametric_table(
  bucket : Int32,
  n : Int32,
  bit_depth : Int32,
  parametric_curve : ParametricCurve,
) -> FixedArray[Float] {
  let cap = Float::from_int((1 << bit_depth) - 1)
  let scale = (1.0 : Float) / Float::from_int(n - 1)
  let table = FixedArray::make(bucket, (0.0 : Float))
  for v in 0..<n.min(bucket) {
    table[v] = cap * parametric_curve.eval(Float::from_int(v) * scale)
  }
  table
}

///|
fn compare_parametric(src : FixedArray[Float], dst : FixedArray[Float]) -> Bool {
  let n = src.length().min(dst.length())
  for i in 0..<n {
    if fabs(src[i] - dst[i]) > 1.0e-4 {
      return false
    }
  }
  true
}

///|
fn lut_inverse_interp16(value : Int32, lut_table : FixedArray[Int32]) -> Int32 {
  let mut l = 1
  let mut r = 0x10000
  let mut x = 0
  let length = lut_table.length()
  let mut num_zeroes = 0
  for item in lut_table {
    if item == 0 {
      num_zeroes += 1
    } else {
      break
    }
  }
  if num_zeroes == 0 && value == 0 {
    return 0
  }
  let mut num_of_polys = 0
  for i = length - 1; i >= 0; i = i - 1 {
    if lut_table[i] == 0xffff {
      num_of_polys += 1
    } else {
      break
    }
  }
  // Does the curve belong to this case?
  if num_zeroes > 1 || num_of_polys > 1 {
    // Identify if value fall downto 0 or FFFF zone
    if value == 0 {
      return 0
    }
    if num_zeroes > 1 {
      let a_0 = (num_zeroes - 1) * 0xffff / (length - 1)
      l = a_0 - 1
    }
    if num_of_polys > 1 {
      let b_0 = (length - 1 - num_of_polys) * 0xffff / (length - 1)
      r = b_0 + 1
    }
  }
  if r <= l {
    // If this happens LutTable is not invertible
    return 0
  }
  while r > l {
    x = (l + r) / 2
    let res = lut_interp_linear16((x - 1) & 0xFFFF, lut_table)
    if res == value {
      // Found exact match.
      return (x - 1) & 0xFFFF
    }
    if res > value {
      r = x - 1
    } else {
      l = x + 1
    }
  }
  // Not found, should we interpolate?
  let val2 = (length - 1).to_double() * ((x - 1).to_double() / 65535.0)
  let cell0 = d2i(val2.floor())
  let cell1 = d2i(val2.ceil())
  if cell0 == cell1 {
    return x & 0xFFFF
  }
  let y0 = lut_table[cell0].to_double()
  let x0 = 65535.0 * cell0.to_double() / (length - 1).to_double()
  let y1 = lut_table[cell1].to_double()
  let x1 = 65535.0 * cell1.to_double() / (length - 1).to_double()
  let a = (y1 - y0) / (x1 - x0)
  let b = y0 + -a * x0
  if dabs(a) < 0.01 {
    return x & 0xFFFF
  }
  let f = (value.to_double() - b) / a
  if f < 0.0 {
    return 0
  }
  if f >= 65535.0 {
    return 0xffff
  }
  d2u16((f + 0.5).floor())
}

///|
fn invert_lut(
  table : FixedArray[Int32],
  out_length : Int32,
) -> FixedArray[Int32] {
  let output = FixedArray::make(out_length, 0)
  let scale_value = 65535.0 / (out_length - 1).to_double()
  for i in 0..<out_length {
    let x = i.to_double() * scale_value
    let input = d2u16((x + 0.5).floor())
    output[i] = lut_inverse_interp16(input, table)
  }
  output
}

///|
/// `ToneReprCurve::build_linearize_table::<f32, N, BIT_DEPTH>`.
fn ToneReprCurve::build_linearize_table(
  self : ToneReprCurve,
  n : Int32,
) -> FixedArray[Float]? {
  match self {
    Parametric(params) => linear_curve_parametric(n, params)
    Lut(data) =>
      match data.length() {
        0 => Some(passthrough_table(n))
        1 => Some(linear_forward_table(n, data[0]))
        _ => Some(linear_lut_interpolate(n, data))
      }
  }
}

///|
/// `ToneReprCurve::build_gamma_table::<f32, BUCKET, N, BIT_DEPTH>`.
fn ToneReprCurve::build_gamma_table(
  self : ToneReprCurve,
  bucket : Int32,
  n : Int32,
  bit_depth : Int32,
) -> FixedArray[Float]? {
  match self {
    Parametric(params) => {
      if params.length() == 5 {
        let srgb_params : FixedArray[Float] = [
          2.4,
          (1.0 : Float) / (1.055 : Float),
          (0.055 : Float) / (1.055 : Float),
          (1.0 : Float) / (12.92 : Float),
          0.04045,
        ]
        let rec709_params = create_rec709_parametric()
        let lc_params = FixedArray::make(5, (0.0 : Float))
        for i in 0..<5 {
          lc_params[i] = params[i]
        }
        if compare_parametric(lc_params, srgb_params) {
          return Some(TransferCharacteristics::Srgb.make_gamma_table(bucket, n))
        }
        if compare_parametric(lc_params, rec709_params) {
          return Some(
            TransferCharacteristics::Bt709.make_gamma_table(bucket, n),
          )
        }
      }
      guard ParametricCurve::new(params) is Some(parametric_curve) else {
        return None
      }
      if parametric_curve.invert() is Some(x) {
        return Some(make_gamma_parametric_table(bucket, n, bit_depth, x))
      }
      let inverted_size = n
      guard linear_curve_parametric_s(n, params) is Some(gamma_table) else {
        return None
      }
      let gamma_table_uint = FixedArray::make(n, 0)
      for i in 0..<n {
        gamma_table_uint[i] = f2u16(gamma_table[i] * 65535.0)
      }
      let inverted = invert_lut(gamma_table_uint, inverted_size)
      Some(make_gamma_lut(bucket, n, inverted))
    }
    Lut(data) =>
      match data.length() {
        0 => Some(make_gamma_linear_table(bucket, n))
        1 =>
          Some(
            make_gamma_pow_table(
              bucket,
              n,
              (1.0 : Float) / u8_fixed_8number_to_float(data[0]),
              bit_depth,
            ),
          )
        _ => {
          let mut inverted_size = data.length()
          if inverted_size < 256 {
            inverted_size = 256
          }
          let inverted = invert_lut(data, inverted_size)
          Some(make_gamma_lut(bucket, n, inverted))
        }
      }
  }
}

///|
fn ColorProfile::build_gray_linearize_table(
  self : ColorProfile,
  n : Int32,
) -> FixedArray[Float] raise CmsError {
  match self.gray_trc {
    Some(trc) =>
      match trc.build_linearize_table(n) {
        Some(t) => t
        None => raise BuildTransferFunction
      }
    None => raise BuildTransferFunction
  }
}

///|
fn ColorProfile::build_linearize_table_for(
  self : ColorProfile,
  trc : ToneReprCurve?,
  n : Int32,
  use_cicp : Bool,
) -> FixedArray[Float] raise CmsError {
  if use_cicp && self.cicp is Some(c) {
    let tc = c.transfer_characteristics
    if tc.has_transfer_curve() {
      return tc.make_linear_table(n)
    }
  }
  match trc {
    Some(trc) =>
      match trc.build_linearize_table(n) {
        Some(t) => t
        None => raise BuildTransferFunction
      }
    None => raise BuildTransferFunction
  }
}

///|
fn ColorProfile::build_r_linearize_table(
  self : ColorProfile,
  n : Int32,
  use_cicp : Bool,
) -> FixedArray[Float] raise CmsError {
  self.build_linearize_table_for(self.red_trc, n, use_cicp)
}

///|
fn ColorProfile::build_g_linearize_table(
  self : ColorProfile,
  n : Int32,
  use_cicp : Bool,
) -> FixedArray[Float] raise CmsError {
  self.build_linearize_table_for(self.green_trc, n, use_cicp)
}

///|
fn ColorProfile::build_b_linearize_table(
  self : ColorProfile,
  n : Int32,
  use_cicp : Bool,
) -> FixedArray[Float] raise CmsError {
  self.build_linearize_table_for(self.blue_trc, n, use_cicp)
}

///|
/// `ColorProfile::build_gamma_table::<f32, BUCKET, N, BIT_DEPTH>`.
fn ColorProfile::build_gamma_table(
  self : ColorProfile,
  trc : ToneReprCurve?,
  bucket : Int32,
  n : Int32,
  bit_depth : Int32,
  use_cicp : Bool,
) -> FixedArray[Float] raise CmsError {
  if use_cicp && self.cicp is Some(c) {
    let tc = c.transfer_characteristics
    if tc.has_transfer_curve() {
      return tc.make_gamma_table(bucket, n)
    }
  }
  match trc {
    Some(trc) =>
      match trc.build_gamma_table(bucket, n, bit_depth) {
        Some(t) => t
        None => raise BuildTransferFunction
      }
    None => raise BuildTransferFunction
  }
}

///|
fn ColorProfile::are_all_trc_the_same(self : ColorProfile) -> Bool {
  if self.color_space == Gray {
    return true
  }
  if (self.red_trc, self.green_trc, self.blue_trc)
    is (Some(r), Some(g), Some(b)) {
    match (r, g, b) {
      (Lut(_), Lut(_), Lut(_))
      | (Parametric(_), Parametric(_), Parametric(_)) => ()
      _ => return false
    }
    if r.same(g) || g.same(b) {
      return true
    }
  }
  false
}

///|
fn ColorProfile::is_linear_matrix_shaper(self : ColorProfile) -> Bool {
  if !self.is_matrix_shaper() {
    return false
  }
  if !self.are_all_trc_the_same() {
    return false
  }
  match self.red_trc {
    Some(Lut(lut)) => lut.length() == 0 || is_curve_linear16(lut)
    Some(Parametric(params)) =>
      match ParametricCurve::new(params) {
        Some(curve) => curve.is_linear()
        None => false
      }
    None => false
  }
}

///|
/// `matan::is_curve_linear16`.
fn is_curve_linear16(curve : FixedArray[Int32]) -> Bool {
  let scale = (1.0 : Float) / Float::from_int(curve.length() - 1) * 65535.0
  for index in 0..<curve.length() {
    let quantized = f2u16(fround(Float::from_int(index) * scale))
    let diff = (quantized - curve[index]).abs()
    if diff > 0x0f {
      return false
    }
  }
  true
}
