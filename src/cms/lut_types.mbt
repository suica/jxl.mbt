// LUT tag types (lut8, lut16, lutAtoB, lutBtoA), ported from Little CMS 2.19 (as vendored by lcms2-sys 4.0.7)
// `cmstypes.c`.

///|
/// `uipow`: n * a^b with overflow check (-1 on overflow).
fn uipow(n : Int32, a : Int32, b : Int32) -> Int32 {
  if a == 0 || n == 0 {
    return 0
  }
  let mut rv : UInt64 = 1
  for _ in 0..<b {
    rv = rv * a.to_uint64()
    if rv > 0xFFFFFFFFUL / a.to_uint64() {
      return -1
    }
  }
  let rc = rv * n.to_uint64()
  if rc > 0x7FFFFFFFUL {
    return -1
  }
  rc.to_int()
}

///|
fn read_matrix9(r : Reader) -> FixedArray[Double] raise @bitstream.JxlError {
  let m = FixedArray::make(9, 0.0)
  for i in 0..<9 {
    m[i] = r.s15f16()
  }
  m
}

///|
/// `Read8bitTables`
fn read_8bit_tables(
  r : Reader,
  lut : Pipeline,
  n_channels : Int32,
) -> Unit raise @bitstream.JxlError {
  if n_channels > CMS_MAXCHANNELS || n_channels <= 0 {
    raise cms_error("IccParseFailure: invalid lut8 channels")
  }
  let curves = []
  r.need(256 * n_channels)
  for _ in 0..<n_channels {
    let t = FixedArray::make(256, 0)
    for j in 0..<256 {
      t[j] = from_8_to_16(r.u8())
    }
    curves.push(ToneCurve::tabulated16(t))
  }
  lut.push(stage_curves(curves))
}

///|
/// `Type_LUT8_Read`
fn read_lut8(r : Reader) -> Pipeline raise @bitstream.JxlError {
  let in_ch = r.u8()
  let out_ch = r.u8()
  let clut_points = r.u8()
  if clut_points == 1 {
    raise cms_error("IccParseFailure: invalid CLUT points")
  }
  r.u8() |> ignore
  if in_ch == 0 || in_ch > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lut8 input channels")
  }
  if out_ch == 0 || out_ch > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lut8 output channels")
  }
  let lut = Pipeline::new(in_ch, out_ch)
  let matrix = read_matrix9(r)
  // Only operates if not identity...
  if in_ch == 3 && !mat3_is_identity(matrix) {
    lut.insert_begin(stage_matrix(3, 3, matrix, None))
  }
  read_8bit_tables(r, lut, in_ch)
  let n_tab_size = uipow(out_ch, clut_points, in_ch)
  if n_tab_size == -1 {
    raise cms_error("IccParseFailure: CLUT too large")
  }
  if n_tab_size > 0 {
    r.need(n_tab_size)
    let t = FixedArray::make(n_tab_size, 0)
    for i in 0..<n_tab_size {
      t[i] = from_8_to_16(r.u8())
    }
    lut.push(
      stage_clut16(
        FixedArray::make(MAX_INPUT_DIMENSIONS, clut_points),
        in_ch,
        out_ch,
        t,
      ),
    )
  }
  read_8bit_tables(r, lut, out_ch)
  lut
}

///|
/// `Read16bitTables`
fn read_16bit_tables(
  r : Reader,
  lut : Pipeline,
  n_channels : Int32,
  n_entries : Int32,
) -> Unit raise @bitstream.JxlError {
  // Maybe an empty table? (this is a lcms extension)
  if n_entries <= 0 {
    return
  }
  if n_entries < 2 || n_channels > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lut16 tables")
  }
  let curves = []
  for _ in 0..<n_channels {
    r.need(2 * n_entries)
    let t = FixedArray::make(n_entries, 0)
    for j in 0..<n_entries {
      t[j] = r.u16()
    }
    curves.push(ToneCurve::tabulated16(t))
  }
  lut.push(stage_curves(curves))
}

///|
/// `Type_LUT16_Read`
fn read_lut16(r : Reader) -> Pipeline raise @bitstream.JxlError {
  let in_ch = r.u8()
  let out_ch = r.u8()
  let clut_points = r.u8()
  r.u8() |> ignore
  if in_ch == 0 || in_ch > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lut16 input channels")
  }
  if out_ch == 0 || out_ch > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lut16 output channels")
  }
  let lut = Pipeline::new(in_ch, out_ch)
  let matrix = read_matrix9(r)
  // Only operates on 3 channels
  if in_ch == 3 && !mat3_is_identity(matrix) {
    lut.push(stage_matrix(3, 3, matrix, None))
  }
  let input_entries = r.u16()
  let output_entries = r.u16()
  if input_entries > 0x7FFF || output_entries > 0x7FFF {
    raise cms_error("IccParseFailure: too many lut16 entries")
  }
  if clut_points == 1 {
    raise cms_error("IccParseFailure: invalid CLUT points")
  }
  read_16bit_tables(r, lut, in_ch, input_entries)
  let n_tab_size = uipow(out_ch, clut_points, in_ch)
  if n_tab_size == -1 {
    raise cms_error("IccParseFailure: CLUT too large")
  }
  if n_tab_size > 0 {
    r.need(2 * n_tab_size)
    let t = FixedArray::make(n_tab_size, 0)
    for i in 0..<n_tab_size {
      t[i] = r.u16()
    }
    lut.push(
      stage_clut16(
        FixedArray::make(MAX_INPUT_DIMENSIONS, clut_points),
        in_ch,
        out_ch,
        t,
      ),
    )
  }
  read_16bit_tables(r, lut, out_ch, output_entries)
  lut
}

///|
/// `ReadMatrix` (3x3 plus offset) of lutAtoB/lutBtoA.
fn read_ab_matrix(
  r : Reader,
  offset : Int32,
) -> Stage raise @bitstream.JxlError {
  r.pos = offset
  let m = read_matrix9(r)
  let off = FixedArray::make(3, 0.0)
  for i in 0..<3 {
    off[i] = r.s15f16()
  }
  stage_matrix(3, 3, m, Some(off))
}

///|
/// `ReadCLUT` of lutAtoB/lutBtoA.
fn read_ab_clut(
  r : Reader,
  offset : Int32,
  in_ch : Int32,
  out_ch : Int32,
) -> Stage raise @bitstream.JxlError {
  r.pos = offset
  let grid_points = FixedArray::make(MAX_INPUT_DIMENSIONS, 0)
  r.need(CMS_MAXCHANNELS)
  for i in 0..<CMS_MAXCHANNELS {
    let g = r.u8()
    if g == 1 {
      raise cms_error("IccParseFailure: invalid CLUT grid points")
    }
    if i < MAX_INPUT_DIMENSIONS {
      grid_points[i] = g
    }
  }
  let precision = r.u8()
  r.u8() |> ignore
  r.u8() |> ignore
  r.u8() |> ignore
  let n = out_ch * cube_size(grid_points, in_ch)
  if n == 0 {
    raise cms_error("IccParseFailure: invalid CLUT")
  }
  let t = FixedArray::make(n, 0)
  if precision == 1 {
    r.need(n)
    for i in 0..<n {
      t[i] = from_8_to_16(r.u8())
    }
  } else if precision == 2 {
    r.need(2 * n)
    for i in 0..<n {
      t[i] = r.u16()
    }
  } else {
    raise cms_error("IccParseFailure: unknown CLUT precision")
  }
  stage_clut16(grid_points, in_ch, out_ch, t)
}

///|
/// `ReadSetOfCurves`
fn read_set_of_curves(
  r : Reader,
  offset : Int32,
  n_curves : Int32,
) -> Stage raise @bitstream.JxlError {
  if n_curves > CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: too many curves")
  }
  r.pos = offset
  let curves = []
  for _ in 0..<n_curves {
    curves.push(read_embedded_curve(r))
    r.align()
  }
  stage_curves(curves)
}

///|
/// `Type_LUTA2B_Read`: A - CLUT - M - Matrix - B
fn read_lut_atob(
  r : Reader,
  base : Int32,
) -> Pipeline raise @bitstream.JxlError {
  let in_ch = r.u8()
  let out_ch = r.u8()
  r.u16() |> ignore
  let offset_b = r.u32().reinterpret_as_int()
  let offset_mat = r.u32().reinterpret_as_int()
  let offset_m = r.u32().reinterpret_as_int()
  let offset_c = r.u32().reinterpret_as_int()
  let offset_a = r.u32().reinterpret_as_int()
  if in_ch == 0 || in_ch >= CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lutAtoB input channels")
  }
  if out_ch == 0 || out_ch >= CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lutAtoB output channels")
  }
  let lut = Pipeline::new(in_ch, out_ch)
  if offset_a != 0 {
    lut.push(read_set_of_curves(r, base + offset_a, in_ch))
  }
  if offset_c != 0 {
    lut.push(read_ab_clut(r, base + offset_c, in_ch, out_ch))
  }
  if offset_m != 0 {
    lut.push(read_set_of_curves(r, base + offset_m, out_ch))
  }
  if offset_mat != 0 {
    lut.push(read_ab_matrix(r, base + offset_mat))
  }
  if offset_b != 0 {
    lut.push(read_set_of_curves(r, base + offset_b, out_ch))
  }
  lut
}

///|
/// `Type_LUTB2A_Read`: B - Matrix - M - CLUT - A
fn read_lut_btoa(
  r : Reader,
  base : Int32,
) -> Pipeline raise @bitstream.JxlError {
  let in_ch = r.u8()
  let out_ch = r.u8()
  if in_ch == 0 || in_ch >= CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lutBtoA input channels")
  }
  if out_ch == 0 || out_ch >= CMS_MAXCHANNELS {
    raise cms_error("IccParseFailure: invalid lutBtoA output channels")
  }
  r.u16() |> ignore
  let offset_b = r.u32().reinterpret_as_int()
  let offset_mat = r.u32().reinterpret_as_int()
  let offset_m = r.u32().reinterpret_as_int()
  let offset_c = r.u32().reinterpret_as_int()
  let offset_a = r.u32().reinterpret_as_int()
  let lut = Pipeline::new(in_ch, out_ch)
  if offset_b != 0 {
    lut.push(read_set_of_curves(r, base + offset_b, in_ch))
  }
  if offset_mat != 0 {
    lut.push(read_ab_matrix(r, base + offset_mat))
  }
  if offset_m != 0 {
    lut.push(read_set_of_curves(r, base + offset_m, in_ch))
  }
  if offset_c != 0 {
    lut.push(read_ab_clut(r, base + offset_c, in_ch, out_ch))
  }
  if offset_a != 0 {
    lut.push(read_set_of_curves(r, base + offset_a, out_ch))
  }
  lut
}

///|
/// Reads an AToB/BToA tag as a pipeline and returns it with its tag type.
fn Profile::read_lut_tag(
  self : Profile,
  sig : UInt32,
  is_a2b : Bool,
) -> (Pipeline, UInt32)? raise @bitstream.JxlError {
  guard self.open_tag(sig) is Some((r, ty, entry)) else { return None }
  let lut = if ty == SIG_LUT16_TYPE {
    read_lut16(r)
  } else if ty == SIG_LUT8_TYPE {
    read_lut8(r)
  } else if ty == SIG_LUT_ATOB_TYPE && is_a2b {
    read_lut_atob(r, entry.offset)
  } else if ty == SIG_LUT_BTOA_TYPE && !is_a2b {
    read_lut_btoa(r, entry.offset)
  } else if ty == SIG_MULTI_PROCESS_ELEMENT_TYPE {
    raise @bitstream.JxlError::NotSupported(
      "UnsupportedIccProfile: multiProcessElementType",
    )
  } else {
    raise cms_error("IccParseFailure: unsupported LUT tag type")
  }
  Some((lut, ty))
}
