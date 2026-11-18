// SSIMULACRA2 (port of the `ssimulacra2` crate 0.5.1 and the parts of
// `yuvxyb` 0.4.2 it uses), the metric of jxl-oxide-tests' cms test.
// `mul_add` is fused as upstream's (the SSIM terms subtract nearly equal
// blurred values, so the rounding shows in the score); the helpers are copies
// of `src/color/fastmath.mbt`'s.

///|
const NUM_SCALES : Int = 6

///|
/// Fused multiply-add on `Float`: computes `a * b + c` with a single rounding,
/// like Rust's `f32::mul_add`.
///
/// The product of two f32 values is exact in f64, so only the final addition
/// can introduce double rounding (f64 then f32); that case is detected and
/// corrected as in musl's `fmaf`.
fn mul_add(a : Float, b : Float, c : Float) -> Float {
  let xy = a.to_double() * b.to_double()
  let z = c.to_double()
  let result = xy + z
  let bits = result.reinterpret_as_uint64()
  let e = ((bits >> 52) & 0x7ffUL).to_int()
  // Common case: the double precision result is fine.
  if (bits & 0x1fffffffUL) != 0x10000000UL ||
    e == 0x7ff ||
    (result - xy == z && result - z == xy) {
    return Float::from_double(result)
  }
  // `result` is exactly halfway between two floats and inexact: nudge it
  // towards the exact value so that the f32 rounding goes the right way.
  let neg = bits >> 63 != 0UL
  let err = if neg == (z > xy) { xy - result + z } else { z - result + xy }
  let adjusted = if neg == (err < 0.0) { bits + 1UL } else { bits - 1UL }
  Float::from_double(adjusted.reinterpret_as_double())
}

///|
/// Fused multiply-add on `Double` (`f64::mul_add`), computed with an exact
/// product (Dekker's algorithm) followed by a compensated sum.
///
/// This is not correctly rounded in every case, but it is within one ulp of
/// the exact result and exact for all non-pathological inputs.
fn mul_add_d(a : Double, b : Double, c : Double) -> Double {
  let p = a * b
  if p.is_inf() || p.is_nan() || c.is_inf() || c.is_nan() {
    return p + c
  }
  // Dekker split
  let split = 134217729.0 // 2^27 + 1
  let ta = split * a
  let ahi = ta - (ta - a)
  let alo = a - ahi
  let tb = split * b
  let bhi = tb - (tb - b)
  let blo = b - bhi
  let perr = ahi * bhi - p + ahi * blo + alo * bhi + alo * blo
  // two-sum of p and c
  let s = p + c
  let bb = s - p
  let serr = p - (s - bb) + (c - bb)
  s + (perr + serr)
}


///|
/// Recursive Gaussian constants (ssimulacra2 build.rs, sigma 1.5).
priv struct GaussianConsts {
  radius : Int
  vert_mul_in : FixedArray[Float]
  vert_mul_prev : FixedArray[Float]
  mul_in : FixedArray[Float]
  mul_prev : FixedArray[Float]
  mul_prev2 : FixedArray[Float]
}

///|
fn invert3(m : FixedArray[Double]) -> FixedArray[Double] {
  let (a, b, c) = (m[0], m[1], m[2])
  let (d, e, f) = (m[3], m[4], m[5])
  let (g, h, i) = (m[6], m[7], m[8])
  let co_a = e * i - f * h
  let co_b = -(d * i - f * g)
  let co_c = d * h - e * g
  let det = a * co_a + b * co_b + c * co_c
  let inv = 1.0 / det
  [
    co_a * inv,
    -(b * i - c * h) * inv,
    (b * f - c * e) * inv,
    co_b * inv,
    (a * i - c * g) * inv,
    -(a * f - c * d) * inv,
    co_c * inv,
    -(a * h - b * g) * inv,
    (a * e - b * d) * inv,
  ]
}

///|
let gaussian_consts : GaussianConsts = {
  let sigma = 1.5
  let radius = (3.2795 * sigma + 0.2546).round()
  let pi_div_2r = @math.PI / (2.0 * radius)
  let omega = [pi_div_2r, 3.0 * pi_div_2r, 5.0 * pi_div_2r]
  let p_1 = 1.0 / @math.tan(0.5 * omega[0])
  let p_3 = -1.0 / @math.tan(0.5 * omega[1])
  let p_5 = 1.0 / @math.tan(0.5 * omega[2])
  let r_1 = p_1 * p_1 / @math.sin(omega[0])
  let r_3 = -p_3 * p_3 / @math.sin(omega[1])
  let r_5 = p_5 * p_5 / @math.sin(omega[2])
  let neg_half_sigma2 = -0.5 * sigma * sigma
  let recip_radius = 1.0 / radius
  let rho = omega.map(fn(w) { @math.exp(neg_half_sigma2 * w * w) * recip_radius })
  let d_13 = p_1 * r_3 - r_1 * p_3
  let d_35 = p_3 * r_5 - r_3 * p_5
  let d_51 = p_5 * r_1 - r_5 * p_1
  let recip_d13 = 1.0 / d_13
  let zeta_15 = d_35 * recip_d13
  let zeta_35 = d_51 * recip_d13
  let a = invert3([p_1, p_3, p_5, r_1, r_3, r_5, zeta_15, zeta_35, 1.0])
  let gamma = [
    1.0,
    radius * radius - sigma * sigma,
    zeta_15 * rho[0] + zeta_35 * rho[1] + rho[2],
  ]
  let beta = [0, 1, 2].map(fn(r) {
    a[r * 3] * gamma[0] + a[r * 3 + 1] * gamma[1] + a[r * 3 + 2] * gamma[2]
  })
  let vert_mul_in = FixedArray::make(3, (0.0 : Float))
  let vert_mul_prev = FixedArray::make(3, (0.0 : Float))
  let mul_in = FixedArray::make(3, (0.0 : Float))
  let mul_prev = FixedArray::make(3, (0.0 : Float))
  let mul_prev2 = FixedArray::make(3, (0.0 : Float))
  for i in 0..<3 {
    let n2 = -beta[i] * @math.cos(omega[i] * (radius + 1.0))
    let d1 = -2.0 * @math.cos(omega[i])
    vert_mul_in[i] = Float::from_double(n2)
    vert_mul_prev[i] = Float::from_double(d1)
    mul_prev[i] = Float::from_double(-d1)
    mul_prev2[i] = -1.0
    mul_in[i] = Float::from_double(n2)
  }
  {
    radius: radius.to_int(),
    vert_mul_in,
    vert_mul_prev,
    mul_in,
    mul_prev,
    mul_prev2,
  }
}

///|
fn blur_horizontal(
  input : FixedArray[Float],
  output : FixedArray[Float],
  width : Int,
  height : Int,
) -> Unit {
  let k = gaussian_consts
  let big_n = k.radius
  for y in 0..<height {
    let base = y * width
    let mut prev_1 : Float = 0.0
    let mut prev_3 : Float = 0.0
    let mut prev_5 : Float = 0.0
    let mut prev2_1 : Float = 0.0
    let mut prev2_3 : Float = 0.0
    let mut prev2_5 : Float = 0.0
    let mut n = -big_n + 1
    while n < width {
      let left = n - big_n - 1
      let right = n + big_n - 1
      let left_val = if left >= 0 { input[base + left] } else { 0.0 }
      let right_val = if right < width { input[base + right] } else { 0.0 }
      let sum = left_val + right_val
      let mut out_1 = sum * k.mul_in[0]
      let mut out_3 = sum * k.mul_in[1]
      let mut out_5 = sum * k.mul_in[2]
      out_1 = mul_add(k.mul_prev2[0], prev2_1, out_1)
      out_3 = mul_add(k.mul_prev2[1], prev2_3, out_3)
      out_5 = mul_add(k.mul_prev2[2], prev2_5, out_5)
      prev2_1 = prev_1
      prev2_3 = prev_3
      prev2_5 = prev_5
      out_1 = mul_add(k.mul_prev[0], prev_1, out_1)
      out_3 = mul_add(k.mul_prev[1], prev_3, out_3)
      out_5 = mul_add(k.mul_prev[2], prev_5, out_5)
      prev_1 = out_1
      prev_3 = out_3
      prev_5 = out_5
      if n >= 0 {
        output[base + n] = out_1 + out_3 + out_5
      }
      n += 1
    }
  }
}

///|
/// Column-wise pass; columns are independent, so processing them one at a
/// time gives the same result as upstream's chunked passes.
fn blur_vertical(
  input : FixedArray[Float],
  output : FixedArray[Float],
  width : Int,
  height : Int,
) -> Unit {
  let k = gaussian_consts
  let big_n = k.radius
  for x in 0..<width {
    let prev = FixedArray::make(3, (0.0 : Float))
    let prev2 = FixedArray::make(3, (0.0 : Float))
    let mut n = -big_n + 1
    while n < height {
      let top = n - big_n - 1
      let bottom = n + big_n - 1
      let top_val = if top >= 0 { input[top * width + x] } else { 0.0 }
      let bottom_val = if bottom < height {
        input[bottom * width + x]
      } else {
        0.0
      }
      let sum = top_val + bottom_val
      let mut total : Float = 0.0
      for j in 0..<3 {
        let o = mul_add(prev[j], k.vert_mul_prev[j], prev2[j])
        let o = mul_add(sum, k.vert_mul_in[j], -o)
        prev2[j] = prev[j]
        prev[j] = o
        total = total + o
      }
      if n >= 0 {
        // upstream sums out1 + out3 + out5 in this order
        output[n * width + x] = total
      }
      n += 1
    }
  }
}

///|
fn blur_planes(
  img : Array[FixedArray[Float]],
  width : Int,
  height : Int,
) -> Array[FixedArray[Float]] {
  img.map(fn(plane) {
    let temp = FixedArray::make(width * height, (0.0 : Float))
    let out = FixedArray::make(width * height, (0.0 : Float))
    blur_horizontal(plane, temp, width, height)
    blur_vertical(temp, out, width, height)
    out
  })
}

///|
let opsin_absorbance_matrix : FixedArray[Float] = [
  0.30,
  1.0 - 0.078 - 0.30,
  0.078,
  0.23,
  1.0 - 0.078 - 0.23,
  0.078,
  0.24342269,
  0.20476745,
  1.0 - 0.24342269 - 0.20476745,
]

///|
let opsin_absorbance_bias : Float = 0.0037930734

///|
fn cbrtf(x : Float) -> Float {
  Float::from_double(@math.cbrt(x.to_double()))
}

///|
/// Linear RGB (interleaved) to the three planes of positive XYB
/// (`Xyb::from(LinearRgb)` followed by `make_positive_xyb` and
/// `xyb_to_planar`).
fn linear_rgb_to_positive_xyb_planar(
  rgb : FixedArray[Float],
  n : Int,
) -> Array[FixedArray[Float]] {
  let m = opsin_absorbance_matrix
  let neg_bias_cbrt = -cbrtf(opsin_absorbance_bias)
  let out = [
    FixedArray::make(n, (0.0 : Float)),
    FixedArray::make(n, (0.0 : Float)),
    FixedArray::make(n, (0.0 : Float)),
  ]
  for i in 0..<n {
    let r = rgb[i * 3]
    let g = rgb[i * 3 + 1]
    let b = rgb[i * 3 + 2]
    let mixed = FixedArray::make(3, (0.0 : Float))
    for c in 0..<3 {
      let v = mul_add(
        m[c * 3],
        r,
        mul_add(m[c * 3 + 1], g, mul_add(m[c * 3 + 2], b, opsin_absorbance_bias)),
      )
      let v : Float = if v < 0.0 { 0.0 } else { v }
      mixed[c] = cbrtf(v) + neg_bias_cbrt
    }
    let x : Float = 0.5 * (mixed[0] - mixed[1])
    let y : Float = 0.5 * (mixed[0] + mixed[1])
    let bb = mixed[2]
    // make_positive_xyb
    out[2][i] = bb - y + (0.55 : Float)
    out[0][i] = mul_add(x, 14.0, 0.42)
    out[1][i] = y + (0.01 : Float)
  }
  out
}

///|
fn downscale_by_2(
  input : FixedArray[Float],
  in_w : Int,
  in_h : Int,
) -> (FixedArray[Float], Int, Int) {
  let scale = 2
  let out_w = (in_w + scale - 1) / scale
  let out_h = (in_h + scale - 1) / scale
  let out = FixedArray::make(out_w * out_h * 3, (0.0 : Float))
  let normalize : Float = 1.0 / Float::from_int(scale * scale)
  for oy in 0..<out_h {
    for ox in 0..<out_w {
      for c in 0..<3 {
        let mut sum : Float = 0.0
        for iy in 0..<scale {
          for ix in 0..<scale {
            let x = @cmp.minimum(ox * scale + ix, in_w - 1)
            let y = @cmp.minimum(oy * scale + iy, in_h - 1)
            sum = sum + input[(y * in_w + x) * 3 + c]
          }
        }
        out[(oy * out_w + ox) * 3 + c] = sum * normalize
      }
    }
  }
  (out, out_w, out_h)
}

///|
fn image_multiply(
  a : Array[FixedArray[Float]],
  b : Array[FixedArray[Float]],
) -> Array[FixedArray[Float]] {
  [0, 1, 2].map(fn(c) {
    FixedArray::makei(a[c].length(), fn(i) { a[c][i] * b[c][i] })
  })
}

///|
fn ssim_map(
  width : Int,
  height : Int,
  m1 : Array[FixedArray[Float]],
  m2 : Array[FixedArray[Float]],
  s11 : Array[FixedArray[Float]],
  s22 : Array[FixedArray[Float]],
  s12 : Array[FixedArray[Float]],
) -> FixedArray[Double] {
  let c2 : Float = 0.0009
  let one_per_pixels = 1.0 / (width * height).to_double()
  let plane_averages = FixedArray::make(6, 0.0)
  for c in 0..<3 {
    let mut sum0 = 0.0
    let mut sum1 = 0.0
    for i in 0..<(width * height) {
      let mu1 = m1[c][i]
      let mu2 = m2[c][i]
      let mu11 = mu1 * mu1
      let mu22 = mu2 * mu2
      let mu12 = mu1 * mu2
      let mu_diff = mu1 - mu2
      let num_m = mul_add(mu_diff, -mu_diff, 1.0)
      let num_s = mul_add(2.0, s12[c][i] - mu12, c2)
      let denom_s = s11[c][i] - mu11 + (s22[c][i] - mu22) + c2
      let mut d = 1.0 - (num_m * num_s / denom_s).to_double()
      // f64::max(d, 0.0), which ignores NaN
      if d.is_nan() || d < 0.0 {
        d = 0.0
      }
      sum0 += d
      sum1 += d * d * d * d
    }
    plane_averages[c * 2] = one_per_pixels * sum0
    plane_averages[c * 2 + 1] = (one_per_pixels * sum1).sqrt().sqrt()
  }
  plane_averages
}

///|
fn edge_diff_map(
  width : Int,
  height : Int,
  img1 : Array[FixedArray[Float]],
  mu1 : Array[FixedArray[Float]],
  img2 : Array[FixedArray[Float]],
  mu2 : Array[FixedArray[Float]],
) -> FixedArray[Double] {
  let one_per_pixels = 1.0 / (width * height).to_double()
  let plane_averages = FixedArray::make(12, 0.0)
  for c in 0..<3 {
    let sum1 = FixedArray::make(4, 0.0)
    for i in 0..<(width * height) {
      let d1 = (1.0 + (img2[c][i] - mu2[c][i]).abs().to_double()) /
        (1.0 + (img1[c][i] - mu1[c][i]).abs().to_double()) -
        1.0
      let artifact = if d1 > 0.0 { d1 } else { 0.0 }
      sum1[0] += artifact
      sum1[1] += artifact * artifact * artifact * artifact
      let detail_lost = if -d1 > 0.0 { -d1 } else { 0.0 }
      sum1[2] += detail_lost
      sum1[3] += detail_lost * detail_lost * detail_lost * detail_lost
    }
    plane_averages[c * 4] = one_per_pixels * sum1[0]
    plane_averages[c * 4 + 1] = (one_per_pixels * sum1[1]).sqrt().sqrt()
    plane_averages[c * 4 + 2] = one_per_pixels * sum1[2]
    plane_averages[c * 4 + 3] = (one_per_pixels * sum1[3]).sqrt().sqrt()
  }
  plane_averages
}

///|
let ssimulacra2_weight : FixedArray[Double] = [
  0.0,
  0.0007376606707406586,
  0.0,
  0.0,
  0.0007793481682867309,
  0.0,
  0.0,
  0.0004371155730107379,
  0.0,
  1.1041726426657346,
  0.00066284834129271,
  0.00015231632783718752,
  0.0,
  0.0016406437456599754,
  0.0,
  1.8422455520539298,
  11.441172603757666,
  0.0,
  0.0007989109436015163,
  0.000176816438078653,
  0.0,
  1.8787594979546387,
  10.94906990605142,
  0.0,
  0.0007289346991508072,
  0.9677937080626833,
  0.0,
  0.00014003424285435884,
  0.9981766977854967,
  0.00031949755934435053,
  0.0004550992113792063,
  0.0,
  0.0,
  0.0013648766163243398,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  7.466890328078848,
  0.0,
  17.445833984131262,
  0.0006235601634041466,
  0.0,
  0.0,
  6.683678146179332,
  0.00037724407979611296,
  1.027889937768264,
  225.20515300849274,
  0.0,
  0.0,
  19.213238186143016,
  0.0011401524586618361,
  0.001237755635509985,
  176.39317598450694,
  0.0,
  0.0,
  24.43300999870476,
  0.28520802612117757,
  0.0004485436923833408,
  0.0,
  0.0,
  0.0,
  34.77906344483772,
  44.835625328877896,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0008680556573291698,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0005313191874358747,
  0.0,
  0.00016533814161379112,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0004179171803251336,
  0.0017290828234722833,
  0.0,
  0.0020827005846636437,
  0.0,
  0.0,
  8.826982764996862,
  23.19243343998926,
  0.0,
  95.1080498811086,
  0.9863978034400682,
  0.9834382792465353,
  0.0012286405048278493,
  171.2667255897307,
  0.9807858872435379,
  0.0,
  0.0,
  0.0,
  0.0005130064588990679,
  0.0,
  0.00010854057858411537,
]

///|
/// SSIMULACRA2 score of `distorted` against `source`, both interleaved linear
/// RGB (3 floats a pixel) of `width` x `height` (at least 8x8).
pub fn compute_frame_ssimulacra2(
  source : FixedArray[Float],
  distorted : FixedArray[Float],
  width : Int,
  height : Int,
) -> Double raise Failure {
  if source.length() != width * height * 3 ||
    distorted.length() != width * height * 3 {
    fail("Source and distorted image width and height must be equal")
  }
  if width < 8 || height < 8 {
    fail("Images must be at least 8x8 pixels")
  }
  let mut img1 = source
  let mut img2 = distorted
  let mut width = width
  let mut height = height
  let scales_ssim : Array[FixedArray[Double]] = []
  let scales_edge : Array[FixedArray[Double]] = []
  for scale in 0..<NUM_SCALES {
    if width < 8 || height < 8 {
      break
    }
    if scale > 0 {
      let (a, w, h) = downscale_by_2(img1, width, height)
      let (b, _, _) = downscale_by_2(img2, width, height)
      img1 = a
      img2 = b
      width = w
      height = h
    }
    let n = width * height
    let p1 = linear_rgb_to_positive_xyb_planar(img1, n)
    let p2 = linear_rgb_to_positive_xyb_planar(img2, n)
    let sigma1_sq = blur_planes(image_multiply(p1, p1), width, height)
    let sigma2_sq = blur_planes(image_multiply(p2, p2), width, height)
    let sigma12 = blur_planes(image_multiply(p1, p2), width, height)
    let mu1 = blur_planes(p1, width, height)
    let mu2 = blur_planes(p2, width, height)
    scales_ssim.push(
      ssim_map(width, height, mu1, mu2, sigma1_sq, sigma2_sq, sigma12),
    )
    scales_edge.push(edge_diff_map(width, height, p1, mu1, p2, mu2))
  }
  // Msssim::score
  let weight = ssimulacra2_weight
  let mut ssim = 0.0
  let mut i = 0
  for c in 0..<3 {
    for s in 0..<scales_ssim.length() {
      for n in 0..<2 {
        ssim = mul_add_d(weight[i], scales_ssim[s][c * 2 + n].abs(), ssim)
        i += 1
        ssim = mul_add_d(weight[i], scales_edge[s][c * 4 + n].abs(), ssim)
        i += 1
        ssim = mul_add_d(weight[i], scales_edge[s][c * 4 + n + 2].abs(), ssim)
        i += 1
      }
    }
  }
  ssim *= 0.9562382616834844
  ssim = mul_add_d(
    6.248496625763138e-5 * ssim * ssim,
    ssim,
    mul_add_d(2.326765642916932, ssim, -0.020884521182843837 * ssim * ssim),
  )
  if ssim > 0.0 {
    mul_add_d(@math.pow(ssim, 0.6276336467831387), -10.0, 100.0)
  } else {
    100.0
  }
}
