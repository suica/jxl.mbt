///|
let max_num_splines : Int32 = 1 << 24

///|
let max_num_control_points : Int32 = 1 << 20

///|
/// Holds quantized splines
#derive(Debug)
pub(all) struct Splines {
  quant_splines : Array[QuantSpline]
  quant_adjust : Int32
}

///|
pub fn Splines::parse(
  bs : @bitstream.Bitstream,
  header : FrameHeader,
) -> Splines raise @bitstream.JxlError {
  let decoder = @coding.Decoder::parse(bs, 6)
  decoder.begin(bs)
  let num_splines = decoder.read_varint(bs, 2).reinterpret_as_int().to_int64()
  // `(header.width * header.height) as usize` (u32 multiplication)
  let num_pixels = (header.width.reinterpret_as_uint() *
  header.height.reinterpret_as_uint()).to_int64()
  let max_num_splines = @cmp.minimum(max_num_splines.to_int64(), num_pixels / 4)
  if num_splines.reinterpret_as_uint64() >=
    max_num_splines.reinterpret_as_uint64() {
    raise ProfileConformance("too many splines")
  }
  let num_splines = num_splines.to_int() + 1
  let start_points : Array[(Int64, Int64)] = Array::make(num_splines, (0L, 0L))
  let mut prev_point = (
    decoder.read_varint(bs, 1).to_int64(),
    decoder.read_varint(bs, 1).to_int64(),
  )
  start_points[0] = prev_point
  for i in 1..<num_splines {
    let x = decoder.read_varint(bs, 1)
    let y = decoder.read_varint(bs, 1)
    prev_point = (
      prev_point.0 + @bitstream.unpack_signed(x).to_int64(),
      prev_point.1 + @bitstream.unpack_signed(y).to_int64(),
    )
    start_points[i] = prev_point
  }
  let quant_adjust = @bitstream.unpack_signed(decoder.read_varint(bs, 0))
  let splines : Array[QuantSpline] = []
  let mut acc_control_points = 0L
  for start_point in start_points {
    let spline = QuantSpline::parse(
      bs, start_point, num_pixels, decoder, acc_control_points,
    )
    acc_control_points += spline.quant_points.length().to_int64()
    splines.push(spline)
  }
  decoder.finalize()
  { quant_adjust, quant_splines: splines, }
}

///|
/// Estimated area covered by the splines (`Splines::estimate_area`).
pub fn Splines::estimate_area(
  self : Splines,
  base_correlation_xb : (Float, Float)?,
) -> UInt64 {
  let (bx, bb) = match base_correlation_xb {
    Some(v) => v
    None => (0.0, 1.0)
  }
  let corr_x = f32_ceil_to_u64(bx.abs())
  let corr_b = f32_ceil_to_u64(bb.abs())
  let quant_adjust = self.quant_adjust
  let mut total_area = 0UL
  for quant_spline in self.quant_splines {
    let log_color = {
      let color_xyb = FixedArray::make(3, 0UL)
      for c in 0..<3 {
        let mut sum = 0UL
        for q in quant_spline.xyb_dct[c] {
          sum += div_ceil_qa(q.abs().reinterpret_as_uint(), quant_adjust)
        }
        color_xyb[c] = sum
      }
      color_xyb[0] += corr_x * color_xyb[1]
      color_xyb[2] += corr_b * color_xyb[1]
      let mut max = color_xyb[0]
      if color_xyb[1] > max {
        max = color_xyb[1]
      }
      if color_xyb[2] > max {
        max = color_xyb[2]
      }
      log2_ceil(1UL + max).to_uint64()
    }
    let mut width_estimate = 0UL
    for quant_sigma_dct in quant_spline.sigma_dct {
      let quant_sigma_dct = quant_sigma_dct.abs().reinterpret_as_uint()
      let weight = 1UL + div_ceil_qa(quant_sigma_dct, quant_adjust)
      width_estimate += weight * weight * log_color
    }
    total_area += width_estimate * quant_spline.manhattan_distance
  }
  total_area
}

///|
/// `f32::ceil() as u64` (saturating; NaN → 0).
fn f32_ceil_to_u64(x : Float) -> UInt64 {
  let c = x.to_double().ceil()
  if c.is_nan() || c <= 0.0 {
    0UL
  } else if c >= 18446744073709551615.0 {
    18446744073709551615UL
  } else {
    c.to_uint64()
  }
}

///|
/// `x.next_power_of_two().trailing_zeros()`
fn log2_ceil(x : UInt64) -> Int32 {
  if x <= 1UL {
    0
  } else {
    64 - (x - 1UL).clz()
  }
}

///|
fn div_ceil_qa(dividend : UInt32, quant_adjust : Int32) -> UInt64 {
  let dividend = dividend.to_uint64()
  if quant_adjust >= 0 {
    let quant_adjust = quant_adjust.to_uint64()
    (8UL * dividend + 7UL + quant_adjust) / (8UL + quant_adjust)
  } else {
    let abs_quant_adjust = (-quant_adjust.to_int64()).reinterpret_as_uint64()
    dividend + (dividend * abs_quant_adjust + 7UL) / 8UL
  }
}

///|
/// Holds delta-endcoded control points coordinates (without starting point) and quantized DCT32 coefficients
#derive(Debug)
pub(all) struct QuantSpline {
  quant_points : Array[(Int64, Int64)]
  manhattan_distance : UInt64
  xyb_dct : FixedArray[FixedArray[Int32]]
  sigma_dct : FixedArray[Int32]
}

///|
fn QuantSpline::parse(
  bs : @bitstream.Bitstream,
  start_point : (Int64, Int64),
  num_pixels : Int64,
  decoder : @coding.Decoder,
  acc_control_points : Int64,
) -> QuantSpline raise @bitstream.JxlError {
  let num_points = decoder.read_varint(bs, 3).to_int64()
  let acc_num_points = acc_control_points + num_points
  let max_num_points = @cmp.minimum(
    max_num_control_points.to_int64(),
    num_pixels / 2,
  )
  if acc_num_points > max_num_points {
    raise ProfileConformance("too many spline points")
  }
  let quant_points = []
  let mut cur_value = start_point
  let mut cur_delta = (0L, 0L)
  let mut manhattan_distance = 0UL
  quant_points.push(cur_value)
  for _ in 0L..<num_points {
    let prev_value = cur_value
    let delta_x = @bitstream.unpack_signed(decoder.read_varint(bs, 4)).to_int64()
    let delta_y = @bitstream.unpack_signed(decoder.read_varint(bs, 4)).to_int64()
    cur_delta = (cur_delta.0 + delta_x, cur_delta.1 + delta_y)
    manhattan_distance += (cur_delta.0.abs() + cur_delta.1.abs()).reinterpret_as_uint64()
    let nx = checked_add_i64(cur_value.0, cur_delta.0)
    let ny = checked_add_i64(cur_value.1, cur_delta.1)
    cur_value = (nx, ny)
    if cur_value == prev_value {
      raise ValidationFailed(
        "two consecutive control points have the same value",
      )
    }
    quant_points.push(cur_value)
  }
  let xyb_dct : FixedArray[FixedArray[Int32]] = FixedArray::makei(3, _ => {
    FixedArray::make(32, 0)
  })
  for color_dct in xyb_dct {
    for i in 0..<32 {
      color_dct[i] = @bitstream.unpack_signed(decoder.read_varint(bs, 5))
    }
  }
  let sigma_dct = FixedArray::make(32, 0)
  for i in 0..<32 {
    sigma_dct[i] = @bitstream.unpack_signed(decoder.read_varint(bs, 5))
  }
  { quant_points, manhattan_distance, xyb_dct, sigma_dct, }
}

///|
fn checked_add_i64(a : Int64, b : Int64) -> Int64 raise @bitstream.JxlError {
  let r = a + b
  // Overflow iff both operands have the same sign and the result's sign differs.
  if (a >= 0L) == (b >= 0L) && (r >= 0L) != (a >= 0L) {
    raise ValidationFailed("control point overflowed")
  }
  r
}
