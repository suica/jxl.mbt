// Pipeline stages and pipelines, ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7) `cmslut.c`
// (float evaluation) and the `PreOptimize` step of `cmsopt.c`.

///|
/// `cmsStageSignature`: what a stage implements. Matrix stages created for
/// special purposes keep the matrix data but carry a different signature,
/// which matters to `PreOptimize`.
#derive(Eq)
enum StageSig {
  CurveSet
  Matrix
  CLut
  Lab2Xyz
  Xyz2Lab
  LabV2toV4
  LabV4toV2
  /// `cmsSigIdentityElemType` (e.g. `_cmsStageAllocIdentityCLut`)
  Identity
}

///|
priv enum StageData {
  Curves(Array[ToneCurve])
  /// Rows x cols matrix (row-major) with optional offset.
  Mat(FixedArray[Double], FixedArray[Double]?)
  /// 16-bit CLUT evaluated through `EvaluateCLUTfloatIn16`.
  CLut16(InterpParams, FixedArray[Int32])
  Lab2XyzData
  Xyz2LabData
}

///|
priv struct Stage {
  implements : StageSig
  in_ch : Int32
  out_ch : Int32
  data : StageData
}

///|
/// `cmsStageAllocToneCurves`
fn stage_curves(curves : Array[ToneCurve]) -> Stage {
  let n = curves.length()
  { implements: CurveSet, in_ch: n, out_ch: n, data: Curves(curves), }
}

///|
/// `cmsStageAllocMatrix`
fn stage_matrix(
  rows : Int32,
  cols : Int32,
  m : FixedArray[Double],
  offset : FixedArray[Double]?,
) -> Stage {
  let mm = FixedArray::make(rows * cols, 0.0)
  for i in 0..<(rows * cols) {
    mm[i] = m[i]
  }
  let off = match offset {
    Some(o) => {
      let oo = FixedArray::make(rows, 0.0)
      for i in 0..<rows {
        oo[i] = o[i]
      }
      Some(oo)
    }
    None => None
  }
  { implements: Matrix, in_ch: cols, out_ch: rows, data: Mat(mm, off), }
}

///|
fn stage_with_sig(s : Stage, sig : StageSig) -> Stage {
  { ..s, implements: sig, }
}

///|
/// `CubeSize`
fn cube_size(dims : FixedArray[Int32], b : Int32) -> Int32 {
  let mut rv : UInt64 = 1
  for i = b - 1; i >= 0; i = i - 1 {
    let dim = dims[i]
    if dim <= 1 {
      return 0
    }
    // Check for overflow
    if rv > 0xFFFFFFFFUL / dim.to_uint64() {
      return 0
    }
    rv *= dim.to_uint64()
  }
  // Again, prevent overflow
  if rv > 0xFFFFFFFFUL / 15UL {
    return 0
  }
  rv.to_int()
}

///|
/// `cmsStageAllocCLut16bitGranular`
fn stage_clut16(
  grid_points : FixedArray[Int32],
  in_ch : Int32,
  out_ch : Int32,
  table : FixedArray[Int32],
) -> Stage raise @bitstream.JxlError {
  if in_ch > MAX_INPUT_DIMENSIONS {
    raise cms_error("Too many input channels")
  }
  let n = out_ch * cube_size(grid_points, in_ch)
  if n == 0 || table.length() < n {
    raise cms_error("Invalid CLUT")
  }
  let params = InterpParams::new(grid_points, in_ch, out_ch)
  { implements: CLut, in_ch, out_ch, data: CLut16(params, table), }
}

///|
/// `_cmsStageAllocLab2XYZ`
fn stage_lab2xyz() -> Stage {
  { implements: Lab2Xyz, in_ch: 3, out_ch: 3, data: Lab2XyzData, }
}

///|
/// `_cmsStageAllocXYZ2Lab`
fn stage_xyz2lab() -> Stage {
  { implements: Xyz2Lab, in_ch: 3, out_ch: 3, data: Xyz2LabData, }
}

///|
/// `_cmsStageAllocLabV2ToV4`
fn stage_lab_v2_to_v4() -> Stage {
  let k = 65535.0 / 65280.0
  stage_with_sig(
    stage_matrix(3, 3, [k, 0.0, 0.0, 0.0, k, 0.0, 0.0, 0.0, k], None),
    LabV2toV4,
  )
}

///|
/// `_cmsStageAllocLabV4ToV2`
fn stage_lab_v4_to_v2() -> Stage {
  let k = 65280.0 / 65535.0
  stage_with_sig(
    stage_matrix(3, 3, [k, 0.0, 0.0, 0.0, k, 0.0, 0.0, 0.0, k], None),
    LabV4toV2,
  )
}

///|
/// `_cmsStageAllocIdentityCLut` with the identity sampler, 2 grid points.
fn stage_identity_clut(n_chan : Int32) -> Stage raise @bitstream.JxlError {
  let dims = FixedArray::make(MAX_INPUT_DIMENSIONS, 2)
  let n_nodes = cube_size(dims, n_chan)
  let table = FixedArray::make(n_nodes * n_chan, 0)
  // cmsStageSampleCLut16bit with IdentitySampler: node index decomposed with
  // the first input as the most significant digit; _cmsQuantizeVal(0/1, 2).
  for i in 0..<n_nodes {
    let mut rest = i
    for t = n_chan - 1; t >= 0; t = t - 1 {
      let colorant = rest % 2
      rest = rest / 2
      table[i * n_chan + t] = if colorant == 1 { 0xFFFF } else { 0 }
    }
  }
  stage_with_sig(stage_clut16(dims, n_chan, n_chan, table), Identity)
}

///|
/// Scratch space for evaluating a pipeline without allocating per pixel.
priv struct EvalScratch {
  in16 : FixedArray[Int32]
  out16 : FixedArray[Int32]
  interp : InterpScratch
}

///|
fn EvalScratch::new() -> EvalScratch {
  {
    in16: FixedArray::make(MAX_STAGE_CHANNELS, 0),
    out16: FixedArray::make(MAX_STAGE_CHANNELS, 0),
    interp: InterpScratch::new(),
  }
}

///|
/// Float evaluation of one stage (`mpe->EvalPtr`).
fn Stage::eval(
  self : Stage,
  inp : FixedArray[Float],
  out : FixedArray[Float],
  scratch : EvalScratch,
) -> Unit {
  match self.data {
    Curves(curves) =>
      // EvaluateCurves
      for i in 0..<curves.length() {
        out[i] = curves[i].eval_float(inp[i], scratch.out16)
      }
    Mat(m, offset) =>
      // EvaluateMatrix: accumulate in double, store as float
      for i in 0..<self.out_ch {
        let mut tmp = 0.0
        for j in 0..<self.in_ch {
          tmp += inp[j].to_double() * m[i * self.in_ch + j]
        }
        if offset is Some(o) {
          tmp += o[i]
        }
        out[i] = Float::from_double(tmp)
      }
    CLut16(params, table) => {
      // EvaluateCLUTfloatIn16
      for i in 0..<self.in_ch {
        scratch.in16[i] = quick_saturate_word(inp[i].to_double() * 65535.0)
      }
      params.eval16(table, scratch.in16, scratch.out16, scratch.interp)
      for i in 0..<self.out_ch {
        out[i] = Float::from_int(scratch.out16[i]) / Float::from_double(65535.0)
      }
    }
    Lab2XyzData => {
      // EvaluateLab2XYZ (V4 rules)
      let l = inp[0].to_double() * 100.0
      let a = inp[1].to_double() * 255.0 - 128.0
      let b = inp[2].to_double() * 255.0 - 128.0
      let (x, y, z) = lab_to_xyz(l, a, b)
      out[0] = Float::from_double(x / max_encodeable_xyz)
      out[1] = Float::from_double(y / max_encodeable_xyz)
      out[2] = Float::from_double(z / max_encodeable_xyz)
    }
    Xyz2LabData => {
      // EvaluateXYZ2Lab
      let x = inp[0].to_double() * max_encodeable_xyz
      let y = inp[1].to_double() * max_encodeable_xyz
      let z = inp[2].to_double() * max_encodeable_xyz
      let (l, a, b) = xyz_to_lab(x, y, z)
      out[0] = Float::from_double(l / 100.0)
      out[1] = Float::from_double((a + 128.0) / 255.0)
      out[2] = Float::from_double((b + 128.0) / 255.0)
    }
  }
}

///|
/// `cmsPipeline` restricted to float evaluation.
priv struct Pipeline {
  stages : Array[Stage]
  mut in_ch : Int32
  mut out_ch : Int32
}

///|
fn Pipeline::new(in_ch : Int32, out_ch : Int32) -> Pipeline {
  { stages: [], in_ch, out_ch, }
}

///|
/// `BlessLUT`: channel counts follow the first and last stages.
fn Pipeline::bless(self : Pipeline) -> Unit raise @bitstream.JxlError {
  if self.stages.length() > 0 {
    let first = self.stages[0]
    let last = self.stages[self.stages.length() - 1]
    self.in_ch = first.in_ch
    self.out_ch = last.out_ch
    // Check chain consistency
    for i in 1..<self.stages.length() {
      if self.stages[i].in_ch != self.stages[i - 1].out_ch {
        raise cms_error("Pipeline stages mismatch")
      }
    }
  }
}

///|
/// `cmsPipelineInsertStage(lut, cmsAT_END, mpe)`
fn Pipeline::push(self : Pipeline, s : Stage) -> Unit raise @bitstream.JxlError {
  self.stages.push(s)
  self.bless()
}

///|
/// `cmsPipelineInsertStage(lut, cmsAT_BEGIN, mpe)`
fn Pipeline::insert_begin(
  self : Pipeline,
  s : Stage,
) -> Unit raise @bitstream.JxlError {
  self.stages.insert(0, s)
  self.bless()
}

///|
/// `cmsPipelineCat`
fn Pipeline::cat(
  self : Pipeline,
  l2 : Pipeline,
) -> Unit raise @bitstream.JxlError {
  if self.stages.length() == 0 && l2.stages.length() == 0 {
    self.in_ch = l2.in_ch
    self.out_ch = l2.out_ch
  }
  for s in l2.stages {
    self.stages.push(s)
  }
  self.bless()
}

///|
/// `_LUTevalFloat`
fn Pipeline::eval_float(
  self : Pipeline,
  inp : FixedArray[Float],
  out : FixedArray[Float],
  buf0 : FixedArray[Float],
  buf1 : FixedArray[Float],
  scratch : EvalScratch,
) -> Unit {
  for i in 0..<self.in_ch {
    buf0[i] = inp[i]
  }
  let mut phase = 0
  for s in self.stages {
    if phase == 0 {
      s.eval(buf0, buf1, scratch)
    } else {
      s.eval(buf1, buf0, scratch)
    }
    phase = phase ^ 1
  }
  let src = if phase == 0 { buf0 } else { buf1 }
  for i in 0..<self.out_ch {
    out[i] = src[i]
  }
}

///|
/// `_Remove1Op`
fn remove_1op(stages : Array[Stage], op : StageSig) -> Bool {
  let mut any = false
  let mut i = 0
  while i < stages.length() {
    if stages[i].implements == op {
      stages.remove(i) |> ignore
      any = true
    } else {
      i += 1
    }
  }
  any
}

///|
/// `_Remove2Op`
fn remove_2op(stages : Array[Stage], op1 : StageSig, op2 : StageSig) -> Bool {
  let mut any = false
  let mut i = 0
  if stages.length() == 0 {
    return any
  }
  while i < stages.length() {
    if i + 1 >= stages.length() {
      return any
    }
    if stages[i].implements == op1 && stages[i + 1].implements == op2 {
      stages.remove(i + 1) |> ignore
      stages.remove(i) |> ignore
      any = true
    } else {
      i += 1
    }
  }
  any
}

///|
/// `isFloatMatrixIdentity`
fn is_float_matrix_identity(a : FixedArray[Double]) -> Bool {
  let id = mat3_identity()
  for i in 0..<9 {
    if !((id[i] - a[i]).abs() < Float::from_double(0.00001).to_double()) {
      return false
    }
  }
  true
}

///|
/// `_MultiplyMatrix`: joins two adjacent 3x3 matrices.
fn multiply_matrix(stages : Array[Stage]) -> Bool {
  let mut any = false
  let mut i = 0
  if stages.length() == 0 {
    return any
  }
  while i < stages.length() {
    if i + 1 >= stages.length() {
      return any
    }
    let s1 = stages[i]
    let s2 = stages[i + 1]
    if s1.implements == Matrix && s2.implements == Matrix {
      guard s1.data is Mat(m1, off1) && s2.data is Mat(m2, off2) else {
        return false
      }
      // Input offset and output offset should be zero to use this optimization
      if off1 is Some(_) ||
        off2 is Some(_) ||
        s1.in_ch != 3 ||
        s1.out_ch != 3 ||
        s2.in_ch != 3 ||
        s2.out_ch != 3 {
        return false
      }
      let res = mat3_per(m2, m1)
      stages.remove(i + 1) |> ignore
      stages.remove(i) |> ignore
      if !is_float_matrix_identity(res) {
        stages.insert(i, stage_matrix(3, 3, res, None))
      }
      any = true
    } else {
      i += 1
    }
  }
  any
}

///|
/// `PreOptimize`: removes identities and trivial conversion pairs, joins
/// matrices. This is the only optimization lcms2 applies to float transforms.
fn Pipeline::pre_optimize(self : Pipeline) -> Bool {
  let mut any_opt = false
  for ;; {
    let mut opt = false
    opt = remove_1op(self.stages, Identity) || opt
    opt = remove_2op(self.stages, Xyz2Lab, Lab2Xyz) || opt
    opt = remove_2op(self.stages, Lab2Xyz, Xyz2Lab) || opt
    opt = remove_2op(self.stages, LabV4toV2, LabV2toV4) || opt
    opt = remove_2op(self.stages, LabV2toV4, LabV4toV2) || opt
    // The Lab2FloatPCS/FloatPCS2Lab and XYZ2FloatPCS/FloatPCS2XYZ pairs only
    // come from floating point (MPE) tags, which this port does not read.
    opt = multiply_matrix(self.stages) || opt
    if opt {
      any_opt = true
    } else {
      break
    }
  }
  any_opt
}
