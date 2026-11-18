// Tone curves, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmsgamma.c`.

///|
/// One segment of a segmented curve (`cmsCurveSegment`). Only parametric
/// segments are produced by the ICC readers.
priv struct CurveSegment {
  x0 : Double
  x1 : Double
  type_ : Int32
  params : FixedArray[Double]
}

///|
/// `cmsToneCurve`: parametric segments and/or a 16-bit table.
priv struct ToneCurve {
  segments : Array[CurveSegment]
  /// The 16-bit table. Tabulated curves always have one; for parametric
  /// curves lcms2 precomputes it eagerly, here it is computed on demand.
  mut table16 : FixedArray[Int32]?
  mut interp : InterpParams?
}

///|
/// Number of parameters by parametric type (`DefaultCurves`).
fn parametric_param_count(type_ : Int32) -> Int32? {
  let t = type_.abs()
  match t {
    1 => Some(1)
    2 => Some(3)
    3 => Some(4)
    4 => Some(5)
    5 => Some(7)
    6 => Some(4)
    7 => Some(5)
    8 => Some(5)
    108 => Some(1)
    109 => Some(1)
    _ => None
  }
}

///|
/// `cmsBuildTabulatedToneCurve16`
fn ToneCurve::tabulated16(
  table : FixedArray[Int32],
) -> ToneCurve raise @bitstream.JxlError {
  let n = table.length()
  if n > 65530 {
    raise cms_error("Couldn't create tone curve of more than 65530 entries")
  }
  if n == 0 {
    raise cms_error(
      "Couldn't create tone curve with zero segments and no table",
    )
  }
  let interp = InterpParams::new(FixedArray::make(1, n), 1, 1)
  { segments: [], table16: Some(table), interp: Some(interp), }
}

///|
/// `cmsBuildParametricToneCurve`
fn ToneCurve::parametric(
  type_ : Int32,
  params : FixedArray[Double],
) -> ToneCurve raise @bitstream.JxlError {
  guard parametric_param_count(type_) is Some(count) else {
    raise cms_error("Invalid parametric curve type \{type_}")
  }
  let p = FixedArray::make(10, 0.0)
  for i in 0..<count {
    p[i] = params[i]
  }
  {
    segments: [{ x0: minus_inf, x1: plus_inf, type_, params: p, }],
    table16: None,
    interp: None,
  }
}

///|
fn sigmoid_base(k : Double, t : Double) -> Double {
  1.0 / (1.0 + @math.exp(-k * t)) - 0.5
}

///|
fn inverted_sigmoid_base(k : Double, t : Double) -> Double {
  -@math.ln(1.0 / (t + 0.5) - 1.0) / k
}

///|
fn sigmoid_factory(k : Double, t : Double) -> Double {
  let correction = 0.5 / sigmoid_base(k, 1.0)
  correction * sigmoid_base(k, 2.0 * t - 1.0) + 0.5
}

///|
fn inverse_sigmoid_factory(k : Double, t : Double) -> Double {
  let correction = 0.5 / sigmoid_base(k, 1.0)
  (inverted_sigmoid_base(k, (t - 0.5) / correction) + 1.0) / 2.0
}

///|
fn pow(x : Double, y : Double) -> Double {
  @math.pow(x, y)
}

///|
/// `DefaultEvalParametricFn`
fn eval_parametric(
  type_ : Int32,
  params : FixedArray[Double],
  r : Double,
) -> Double {
  match type_ {
    // X = Y ^ Gamma
    1 =>
      if r < 0.0 {
        if (params[0] - 1.0).abs() < MATRIX_DET_TOLERANCE {
          r
        } else {
          0.0
        }
      } else {
        pow(r, params[0])
      }
    // Type 1 Reversed: X = Y ^1/gamma
    -1 =>
      if r < 0.0 {
        if (params[0] - 1.0).abs() < MATRIX_DET_TOLERANCE {
          r
        } else {
          0.0
        }
      } else if params[0].abs() < MATRIX_DET_TOLERANCE {
        plus_inf
      } else {
        pow(r, 1.0 / params[0])
      }
    // CIE 122-1966
    2 =>
      if params[1].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        let disc = -params[2] / params[1]
        if r >= disc {
          let e = params[1] * r + params[2]
          if e > 0.0 {
            pow(e, params[0])
          } else {
            0.0
          }
        } else {
          0.0
        }
      }
    -2 =>
      if params[0].abs() < MATRIX_DET_TOLERANCE ||
        params[1].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        let v = if r < 0.0 {
          0.0
        } else {
          (pow(r, 1.0 / params[0]) - params[2]) / params[1]
        }
        if v < 0.0 {
          0.0
        } else {
          v
        }
      }
    // IEC 61966-3
    3 =>
      if params[1].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        let mut disc = -params[2] / params[1]
        if disc < 0.0 {
          disc = 0.0
        }
        if r >= disc {
          let e = params[1] * r + params[2]
          if e > 0.0 {
            pow(e, params[0]) + params[3]
          } else {
            0.0
          }
        } else {
          params[3]
        }
      }
    -3 =>
      if params[0].abs() < MATRIX_DET_TOLERANCE ||
        params[1].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else if r >= params[3] {
        let e = r - params[3]
        if e > 0.0 {
          (pow(e, 1.0 / params[0]) - params[2]) / params[1]
        } else {
          0.0
        }
      } else {
        -params[2] / params[1]
      }
    // IEC 61966-2.1 (sRGB)
    4 =>
      if r >= params[4] {
        let e = params[1] * r + params[2]
        if e > 0.0 {
          pow(e, params[0])
        } else {
          0.0
        }
      } else {
        r * params[3]
      }
    -4 => {
      let e = params[1] * params[4] + params[2]
      let disc = if e < 0.0 { 0.0 } else { pow(e, params[0]) }
      if r >= disc {
        if params[0].abs() < MATRIX_DET_TOLERANCE ||
          params[1].abs() < MATRIX_DET_TOLERANCE {
          0.0
        } else {
          (pow(r, 1.0 / params[0]) - params[2]) / params[1]
        }
      } else if params[3].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        r / params[3]
      }
    }
    5 =>
      if r >= params[4] {
        let e = params[1] * r + params[2]
        if e > 0.0 {
          pow(e, params[0]) + params[5]
        } else {
          params[5]
        }
      } else {
        r * params[3] + params[6]
      }
    -5 => {
      let disc = params[3] * params[4] + params[6]
      if r >= disc {
        let e = r - params[5]
        if e < 0.0 {
          0.0
        } else if params[0].abs() < MATRIX_DET_TOLERANCE ||
          params[1].abs() < MATRIX_DET_TOLERANCE {
          0.0
        } else {
          (pow(e, 1.0 / params[0]) - params[2]) / params[1]
        }
      } else if params[3].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        (r - params[6]) / params[3]
      }
    }
    6 => {
      let e = params[1] * r + params[2]
      if params[0] == 1.0 {
        e + params[3]
      } else if e < 0.0 {
        params[3]
      } else {
        pow(e, params[0]) + params[3]
      }
    }
    -6 =>
      if params[0].abs() < MATRIX_DET_TOLERANCE ||
        params[1].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        let e = r - params[3]
        if e < 0.0 {
          0.0
        } else {
          (pow(e, 1.0 / params[0]) - params[2]) / params[1]
        }
      }
    7 => {
      let e = params[2] * pow(r, params[0]) + params[3]
      if e <= 0.0 {
        params[4]
      } else {
        params[1] * @math.log10(e) + params[4]
      }
    }
    -7 =>
      if params[0].abs() < MATRIX_DET_TOLERANCE ||
        params[1].abs() < MATRIX_DET_TOLERANCE ||
        params[2].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        pow(
          (pow(10.0, (r - params[4]) / params[1]) - params[3]) / params[2],
          1.0 / params[0],
        )
      }
    8 => params[0] * pow(params[1], params[2] * r + params[3]) + params[4]
    -8 => {
      let disc = r - params[4]
      if disc < 0.0 {
        0.0
      } else if params[0].abs() < MATRIX_DET_TOLERANCE ||
        params[2].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        (@math.ln(disc / params[0]) / @math.ln(params[1]) - params[3]) /
        params[2]
      }
    }
    108 =>
      if params[0].abs() < MATRIX_DET_TOLERANCE {
        0.0
      } else {
        pow(1.0 - pow(1.0 - r, 1.0 / params[0]), 1.0 / params[0])
      }
    -108 => 1.0 - pow(1.0 - pow(r, params[0]), params[0])
    109 => sigmoid_factory(params[0], r)
    -109 => inverse_sigmoid_factory(params[0], r)
    _ => 0.0
  }
}

///|
/// `EvalSegmentedFn`
fn ToneCurve::eval_segmented(self : ToneCurve, r : Double) -> Double {
  for i = self.segments.length() - 1; i >= 0; i = i - 1 {
    let seg = self.segments[i]
    if r > seg.x0 && r <= seg.x1 {
      let out = eval_parametric(seg.type_, seg.params, r)
      if out.is_pos_inf() {
        return plus_inf
      } else if out.is_neg_inf() {
        return minus_inf
      }
      return out
    }
  }
  minus_inf
}

///|
/// Builds the 16-bit approximation table of a parametric curve, as
/// `cmsBuildSegmentedToneCurve` does.
fn ToneCurve::ensure_table16(
  self : ToneCurve,
) -> (FixedArray[Int32], InterpParams) raise @bitstream.JxlError {
  match (self.table16, self.interp) {
    (Some(t), Some(i)) => (t, i)
    _ => {
      let mut n = 4096
      if self.segments.length() == 1 && self.segments[0].type_ == 1 {
        if (self.segments[0].params[0] - 1.0).abs() < 0.001 {
          n = 2
        }
      }
      let table = FixedArray::make(n, 0)
      for i in 0..<n {
        let r = i.to_double() / (n - 1).to_double()
        table[i] = quick_saturate_word(self.eval_segmented(r) * 65535.0)
      }
      let interp = InterpParams::new(FixedArray::make(1, n), 1, 1)
      self.table16 = Some(table)
      self.interp = Some(interp)
      (table, interp)
    }
  }
}

///|
/// `cmsEvalToneCurve16`
fn ToneCurve::eval16(
  self : ToneCurve,
  v : Int32,
  out : FixedArray[Int32],
) -> Int32 {
  let (table, interp) = self.ensure_table16() catch { _ => return 0 }
  lin_lerp_1d(interp, table, v, out)
  out[0]
}

///|
/// `cmsEvalToneCurveFloat`
fn ToneCurve::eval_float(
  self : ToneCurve,
  v : Float,
  tmp : FixedArray[Int32],
) -> Float {
  if self.segments.length() == 0 {
    let inp = quick_saturate_word(v.to_double() * 65535.0)
    let out = self.eval16(inp, tmp)
    return Float::from_double(out.to_double() / 65535.0)
  }
  Float::from_double(self.eval_segmented(v.to_double()))
}

///|
/// `cmsIsToneCurveDescending`
fn ToneCurve::is_descending(self : ToneCurve) -> Bool {
  let (t, _) = self.ensure_table16() catch { _ => return false }
  t[0] > t[t.length() - 1]
}

///|
/// `GetInterval`: surrounding nodes of `inp`, tricky on non-monotonic tables.
fn get_interval(inp : Double, lut : FixedArray[Int32], domain : Int32) -> Int32 {
  if domain < 1 {
    return -1
  }
  if lut[0] < lut[domain] {
    // Table is overall ascending
    for i = domain - 1; i >= 0; i = i - 1 {
      let y0 = lut[i]
      let y1 = lut[i + 1]
      if y0 <= y1 {
        if inp >= y0.to_double() && inp <= y1.to_double() {
          return i
        }
      } else if y1 < y0 {
        if inp >= y1.to_double() && inp <= y0.to_double() {
          return i
        }
      }
    }
  } else {
    // Table is overall descending
    for i in 0..<domain {
      let y0 = lut[i]
      let y1 = lut[i + 1]
      if y0 <= y1 {
        if inp >= y0.to_double() && inp <= y1.to_double() {
          return i
        }
      } else if y1 < y0 {
        if inp >= y1.to_double() && inp <= y0.to_double() {
          return i
        }
      }
    }
  }
  -1
}

///|
/// `cmsReverseToneCurveEx`
fn ToneCurve::reverse_ex(
  self : ToneCurve,
  n_result_samples : Int32,
) -> ToneCurve raise @bitstream.JxlError {
  // Try to reverse it analytically whatever possible
  if self.segments.length() == 1 && self.segments[0].type_ > 0 {
    let seg = self.segments[0]
    if parametric_param_count(seg.type_) is Some(_) {
      return ToneCurve::parametric(-seg.type_, seg.params)
    }
  }
  // Nope, reverse the table.
  let (table, _) = self.ensure_table16()
  let n_entries = table.length()
  let out = FixedArray::make(n_result_samples, 0)
  let ascending = !self.is_descending()
  let mut a = 0.0
  let mut b = 0.0
  for i in 0..<n_result_samples {
    let y = i.to_double() * 65535.0 / (n_result_samples - 1).to_double()
    let j = get_interval(y, table, n_entries - 1)
    if j >= 0 {
      let x1 = table[j].to_double()
      let x2 = table[j + 1].to_double()
      let y1 = j.to_double() * 65535.0 / (n_entries - 1).to_double()
      let y2 = (j + 1).to_double() * 65535.0 / (n_entries - 1).to_double()
      if x1 == x2 {
        out[i] = quick_saturate_word(if ascending { y2 } else { y1 })
        continue
      } else {
        a = (y2 - y1) / (x2 - x1)
        b = y2 - a * x2
      }
    }
    out[i] = quick_saturate_word(a * y + b)
  }
  ToneCurve::tabulated16(out)
}

///|
/// `cmsReverseToneCurve`
fn ToneCurve::reverse(self : ToneCurve) -> ToneCurve raise @bitstream.JxlError {
  self.reverse_ex(4096)
}
