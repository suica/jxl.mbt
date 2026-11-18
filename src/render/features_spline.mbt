// Port of jxl-render features/spline.rs (spline rendering).

///|
/// 2D Point in f32 coordinates
priv struct SplinePoint {
  x : Float
  y : Float
}

///|
fn SplinePoint::new(x : Float, y : Float) -> SplinePoint {
  { x, y }
}

///|
fn SplinePoint::mirror(self : SplinePoint, center : SplinePoint) -> SplinePoint {
  { x: center.x + center.x - self.x, y: center.y + center.y - self.y }
}

///|
fn SplinePoint::norm_squared(self : SplinePoint) -> Float {
  self.x * self.x + self.y * self.y
}

///|
fn SplinePoint::norm(self : SplinePoint) -> Float {
  self.norm_squared().sqrt()
}

///|
impl Add for SplinePoint with add(self, rhs) {
  SplinePoint::new(self.x + rhs.x, self.y + rhs.y)
}

///|
impl Sub for SplinePoint with sub(self, rhs) {
  SplinePoint::new(self.x - rhs.x, self.y - rhs.y)
}

///|
fn SplinePoint::scale(self : SplinePoint, rhs : Float) -> SplinePoint {
  { x: self.x * rhs, y: self.y * rhs }
}

///|
/// Holds control point coordinates and dequantized DCT32 coefficients of XYB
/// channels, σ parameter of the spline
priv struct Spline {
  points : Array[SplinePoint]
  xyb_dct : FixedArray[FixedArray[Float]]
  sigma_dct : FixedArray[Float]
}

///|
priv struct SplineArc {
  point : SplinePoint
  length : Float
}

///|
let spline_channel_weights : FixedArray[Float] = [0.0042, 0.075, 0.07, 0.3333]

///|
fn Spline::dequant(
  quant_points : Array[(Int64, Int64)],
  quant_xyb_dct : FixedArray[FixedArray[Int]],
  quant_sigma_dct : FixedArray[Int],
  quant_adjust : Int,
  base_correlations_xb : (Float, Float)?,
) -> Spline {
  let points = quant_points.map(fn(p) {
    SplinePoint::new(Float::from_int64(p.0), Float::from_int64(p.1))
  })
  let xyb_dct = FixedArray::makei(3, fn(_) { FixedArray::make(32, (0.0 : Float)) })
  let sigma_dct = FixedArray::make(32, (0.0 : Float))
  let quant_adjust = Float::from_int(quant_adjust)
  let inverted_qa : Float = if quant_adjust >= 0.0 {
    1.0 / (1.0 + quant_adjust / 8.0)
  } else {
    1.0 - quant_adjust / 8.0
  }
  for chan_idx in 0..<3 {
    for i in 0..<32 {
      xyb_dct[chan_idx][i] = Float::from_int(quant_xyb_dct[chan_idx][i]) *
        spline_channel_weights[chan_idx] *
        inverted_qa
    }
  }
  let (corr_x, corr_b) = match base_correlations_xb {
    Some(v) => v
    None => ((0.0 : Float), (1.0 : Float))
  }
  for i in 0..<32 {
    xyb_dct[0][i] = xyb_dct[0][i] + corr_x * xyb_dct[1][i]
    xyb_dct[2][i] = xyb_dct[2][i] + corr_b * xyb_dct[1][i]
  }
  for i in 0..<32 {
    sigma_dct[i] = Float::from_int(quant_sigma_dct[i]) *
      spline_channel_weights[3] *
      inverted_qa
  }
  { points, xyb_dct, sigma_dct }
}

///|
fn Spline::get_samples(self : Spline) -> Array[SplineArc] {
  let upsampled_points = self.get_upsampled_points()
  let mut current = upsampled_points[0]
  let mut next_idx = 0
  let all_samples = [{ point: current, length: 1.0 }]
  while next_idx < upsampled_points.length() {
    let mut prev = current
    let mut arclength : Float = 0.0
    while true {
      if next_idx >= upsampled_points.length() {
        all_samples.push({ point: prev, length: arclength })
        break
      }
      let next = upsampled_points[next_idx]
      let arclength_to_next = (next - prev).norm()
      if arclength + arclength_to_next >= 1.0 {
        current = prev +
          (upsampled_points[next_idx] - prev).scale(
            (1.0 - arclength) / arclength_to_next,
          )
        all_samples.push({ point: current, length: 1.0 })
        break
      }
      arclength = arclength + arclength_to_next
      prev = next
      next_idx += 1
    }
  }
  all_samples
}

///|
/// Returns the points for Cetripetal Catmull-Rom spline segments
fn Spline::get_upsampled_points(self : Spline) -> Array[SplinePoint] {
  let s = self.points
  if s.length() == 1 {
    return [s[0]]
  }
  let extended : Array[SplinePoint] = []
  extended.push(s[1].mirror(s[0]))
  for p in s {
    extended.push(p)
  }
  extended.push(s[s.length() - 2].mirror(s[s.length() - 1]))
  let upsampled : Array[SplinePoint] = []
  let zero = SplinePoint::new(0.0, 0.0)
  let p = FixedArray::make(4, zero)
  let t = FixedArray::make(4, (0.0 : Float))
  let a = FixedArray::make(3, zero)
  let b = FixedArray::make(2, zero)
  for i in 0..<(extended.length() - 3) {
    for k in 0..<4 {
      p[k] = extended[i + k]
    }
    upsampled.push(p[1])
    t[0] = 0.0
    for k in 1..<4 {
      // knot sequence with α = 0.25
      t[k] = t[k - 1] + spline_powf((p[k] - p[k - 1]).norm_squared(), 0.25)
    }
    for step in 1..<16 {
      // knot t from t1 to t2
      let knot = t[1] + Float::from_int(step) / 16.0 * (t[2] - t[1])
      for k in 0..<3 {
        a[k] = p[k] +
          (p[k + 1] - p[k]).scale((knot - t[k]) / (t[k + 1] - t[k]))
      }
      for k in 0..<2 {
        b[k] = a[k] +
          (a[k + 1] - a[k]).scale((knot - t[k]) / (t[k + 2] - t[k]))
      }
      // C = ((t2 - t) * B1 + (t - t1) * B2) / (t2 - t1)
      upsampled.push(
        b[0] + (b[1] - b[0]).scale((knot - t[1]) / (t[2] - t[1])),
      )
    }
  }
  upsampled.push(s[s.length() - 1])
  upsampled
}

///|
/// `f32::powf`, computed in f64 and rounded.
fn spline_powf(x : Float, y : Float) -> Float {
  Float::from_double(@math.pow(x.to_double(), y.to_double()))
}

///|
/// `f32::cos`, computed in f64 and rounded.
fn spline_cosf(x : Float) -> Float {
  Float::from_double(@math.cos(x.to_double()))
}

///|
/// `f32::ln(10.0)`
let spline_ln_10 : Float = Float::from_double(@math.ln(10.0))

///|
/// Renders one spline (`render_spline` for one element of
/// `splines.quant_splines`) onto the colour channels `channels`, whose sample
/// (0, 0) is frame pixel (`region_left`, `region_top`).
///
/// `quant_points`, `quant_xyb_dct` and `quant_sigma_dct` are the fields of
/// `QuantSpline`; `quant_adjust` is `Splines::quant_adjust`.
pub fn render_spline_raw(
  frame_width : Int,
  frame_height : Int,
  channels : Array[@grid.Grid[Float]],
  region_left : Int,
  region_top : Int,
  quant_points : Array[(Int64, Int64)],
  quant_xyb_dct : FixedArray[FixedArray[Int]],
  quant_sigma_dct : FixedArray[Int],
  quant_adjust : Int,
  base_correlations_xb : (Float, Float)?,
) -> Unit {
  let spline = Spline::dequant(
    quant_points, quant_xyb_dct, quant_sigma_dct, quant_adjust, base_correlations_xb,
  )
  let all_samples = spline.get_samples()
  let arclength = Float::from_int(all_samples.length()) -
    2.0 +
    all_samples[all_samples.length() - 1].length
  let values = FixedArray::make(3, (0.0 : Float))
  for i, arc in all_samples {
    let arclength_from_start = (1.0 : Float).min(Float::from_int(i) / arclength)
    let t : Float = 31.0 * arclength_from_start
    let sigma = continuous_idct(spline.sigma_dct, t)
    let inv_sigma : Float = 1.0 / sigma
    for c in 0..<3 {
      values[c] = continuous_idct(spline.xyb_dct[c], t) * arc.length
    }
    let max_color = (0.01 : Float).max(values[0].max(values[1]).max(values[2]))
    let max_distance = ((2.0 : Float) * (spline_ln_10 * 3.0 + max_color)).sqrt() *
      sigma.abs()
    let xbegin = (arc.point.x - max_distance + 0.5).floor().to_int()
    let xbegin = if xbegin > 0 { xbegin } else { 0 }
    let xend = (arc.point.x + max_distance + 1.5).floor().to_int()
    let xend = if xend < frame_width { xend } else { frame_width }
    let ybegin = (arc.point.y - max_distance + 0.5).floor().to_int()
    let ybegin = if ybegin > 0 { ybegin } else { 0 }
    let yend = (arc.point.y + max_distance + 1.5).floor().to_int()
    let yend = if yend < frame_height { yend } else { frame_height }
    for channel, buffer in channels {
      let bw = buffer.width
      let bh = buffer.height
      let buf = buffer.buf
      for y in ybegin..<yend {
        let fy = y - region_top
        if fy < 0 {
          continue
        }
        for x in xbegin..<xend {
          let fx = x - region_left
          if fx < 0 {
            continue
          }
          if fx >= bw || fy >= bh {
            break
          }
          let dx = Float::from_int(x) - arc.point.x
          let dy = Float::from_int(y) - arc.point.y
          let distance = (dx * dx + dy * dy).sqrt()
          let sqrt_0125 : Float = 0.353_553_38
          let factor = spline_erf((0.5 * distance + sqrt_0125) * inv_sigma) -
            spline_erf((0.5 * distance - sqrt_0125) * inv_sigma)
          let extra : Float = 0.25 * values[channel] * sigma * factor * factor
          let idx = fy * bw + fx
          buf[idx] = buf[idx] + extra
        }
      }
    }
  }
}

///|
/// `std::f32::consts::PI / 32.0`
let spline_pi_32 : Float = {
  let pi : Float = 3.14159265358979323846264338327950288
  pi / 32.0
}

///|
/// `std::f32::consts::SQRT_2`
let spline_sqrt_2 : Float = 1.41421356237309504880168872420969808

///|
fn continuous_idct(dct : FixedArray[Float], t : Float) -> Float {
  let mut res = dct[0]
  for i in 1..<32 {
    let theta = Float::from_int(i) * spline_pi_32 * (t + 0.5)
    res = res + spline_sqrt_2 * dct[i] * spline_cosf(theta)
  }
  res
}

///|
/// Computes the error function
// L1 error 7e-4.
fn spline_erf(x : Float) -> Float {
  let ax = x.abs()

  // Compute 1 - 1 / ((((x * a + b) * x + c) * x + d) * x + 1)**4
  let denom1 : Float = ax * 7.77394369e-02 + 2.05260015e-04
  let denom2 : Float = denom1 * ax + 2.32120216e-01
  let denom3 : Float = denom2 * ax + 2.77820801e-01
  let denom4 : Float = denom3 * ax + 1.0
  let denom5 = denom4 * denom4
  let inv_denom5 : Float = 1.0 / denom5
  let result : Float = -inv_denom5 * inv_denom5 + 1.0

  // Change sign if needed.
  if x < 0.0 {
    -result
  } else {
    result
  }
}
