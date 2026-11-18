// Frame-side inputs of the reconstruction (the parts of `jxl_frame::Frame`,
// `HfGlobal`, `LfGroup` and decoded pass groups that jxl-jbr reads), and small
// helpers mirroring `jxl_frame::FrameHeader` group geometry,
// `jxl_modular::ChannelShift::from_jpeg_upsampling` and
// `jxl_vardct::DCT8_NATURAL_ORDER`.

///|
/// Geometry and flags of the JPEG XL frame and image header.
pub(all) struct JpegFrameInfo {
  /// `image_header.size.width` / `height`: written into SOF.
  image_width : Int32
  image_height : Int32
  /// `frame_header.width` / `height`.
  width : Int32
  height : Int32
  /// `frame_header.color_sample_width()` / `color_sample_height()`.
  color_sample_width : Int32
  color_sample_height : Int32
  /// `frame_header.jpeg_upsampling` (frame channel order).
  jpeg_upsampling : FixedArray[Int32]
  /// `frame_header.do_ycbcr`.
  do_ycbcr : Bool
  /// `frame_header.group_size_shift`.
  group_size_shift : Int32
}

///|
fn JpegFrameInfo::group_dim(self : JpegFrameInfo) -> Int32 {
  128 << self.group_size_shift
}

///|
fn div_ceil(a : Int32, b : Int32) -> Int32 {
  (a + b - 1) / b
}

///|
fn JpegFrameInfo::groups_per_row(self : JpegFrameInfo) -> Int32 {
  div_ceil(self.color_sample_width, self.group_dim())
}

///|
fn JpegFrameInfo::num_groups(self : JpegFrameInfo) -> Int32 {
  let group_dim = self.group_dim()
  div_ceil(self.color_sample_width, group_dim) *
  div_ceil(self.color_sample_height, group_dim)
}

///|
fn JpegFrameInfo::lf_groups_per_row(self : JpegFrameInfo) -> Int32 {
  div_ceil(self.color_sample_width, self.group_dim() * 8)
}

///|
fn JpegFrameInfo::lf_group_idx_from_group_idx(
  self : JpegFrameInfo,
  group_idx : Int32,
) -> Int32 {
  let groups_per_row = self.groups_per_row()
  let lf_group_col = group_idx % groups_per_row / 8
  let lf_group_row = group_idx / groups_per_row / 8
  lf_group_col + lf_group_row * self.lf_groups_per_row()
}

///|
fn JpegFrameInfo::group_idx_from_coord(
  self : JpegFrameInfo,
  x : Int32,
  y : Int32,
) -> Int32? {
  let shift = 7 + self.group_size_shift
  let group_x = x >> shift
  let group_y = y >> shift
  let group_idx = group_y * self.groups_per_row() + group_x
  if group_x >= self.groups_per_row() || group_idx >= self.num_groups() {
    None
  } else {
    Some(group_idx)
  }
}

///|
/// `FrameHeader::group_size_for`.
fn JpegFrameInfo::group_size_for(
  self : JpegFrameInfo,
  group_idx : Int32,
) -> (Int32, Int32) {
  let group_dim = self.group_dim()
  let width = self.color_sample_width
  let height = self.color_sample_height
  let full_rows = height / group_dim
  let rows_remainder = height % group_dim
  let full_cols = width / group_dim
  let cols_remainder = width % group_dim
  let num_cols = full_cols + (if cols_remainder > 0 { 1 } else { 0 })
  let col = group_idx % num_cols
  let row = group_idx / num_cols
  let w = if col >= full_cols { cols_remainder } else { group_dim }
  let h = if row >= full_rows { rows_remainder } else { group_dim }
  (w, h)
}

///|
/// `jpeg_upsampling` with the first two entries swapped (YCbCr order).
fn JpegFrameInfo::jpeg_upsampling_ycbcr(
  self : JpegFrameInfo,
) -> FixedArray[Int32] {
  let u = self.jpeg_upsampling
  [u[1], u[0], u[2]]
}

///|
/// `ChannelShift::JpegUpsampling`, built by `from_jpeg_upsampling`.
priv struct ChannelShift {
  has_h_subsample : Bool
  h_subsample : Bool
  has_v_subsample : Bool
  v_subsample : Bool
}

///|
fn ChannelShift::from_jpeg_upsampling(
  jpeg_upsampling : FixedArray[Int32],
  idx : Int32,
) -> ChannelShift {
  let upsampling = jpeg_upsampling[idx]
  let mut hscale = false
  let mut vscale = false
  for v in jpeg_upsampling {
    if v == 1 || v == 2 {
      hscale = true
    }
    if v == 1 || v == 3 {
      vscale = true
    }
  }
  let (h, v) = match upsampling {
    0 => (hscale, vscale)
    1 => (false, false)
    2 => (false, vscale)
    3 => (hscale, false)
    _ => abort("Invalid jpeg_upsampling value of \{upsampling}")
  }
  {
    has_h_subsample: hscale,
    h_subsample: h,
    has_v_subsample: vscale,
    v_subsample: v,
  }
}

///|
fn ChannelShift::shift_size(
  self : ChannelShift,
  width : Int32,
  height : Int32,
) -> (Int32, Int32) {
  let width = if self.has_h_subsample {
    let size = div_ceil(width, 2)
    if self.h_subsample {
      size
    } else {
      size * 2
    }
  } else {
    width
  }
  let height = if self.has_v_subsample {
    let size = div_ceil(height, 2)
    if self.v_subsample {
      size
    } else {
      size * 2
    }
  } else {
    height
  }
  (width, height)
}

///|
/// `jxl_vardct::DCT8_NATURAL_ORDER` as (x, y) pairs packed `x | (y << 8)`.
let dct8_natural_order : FixedArray[Int32] = {
  let ret = FixedArray::make(64, 0)
  let bw = 8
  let mut idx = 1 // (0, 0) comes first
  for dist in 1..<(2 * bw) {
    let margin = if dist > bw { dist - bw } else { 0 }
    for order in margin..<(dist - margin) {
      let (x, y) = if dist % 2 == 1 {
        (order, dist - 1 - order)
      } else {
        (dist - 1 - order, order)
      }
      if x < 1 && y < 1 {
        continue
      }
      ret[idx] = x | (y << 8)
      idx += 1
    }
  }
  ret
}

///|
/// Decoded frame data needed for reconstruction (`ParsedFrameData`).
pub(all) struct ParsedFrameData {
  /// Per LF group: quantized LF coefficients (`lf_coeff.lf_quant` image
  /// channels, i16 values, YCbCr order: Y, Cb (X), Cr (B)).
  lf_quant : Array[FixedArray[@grid.Grid[Int32]]]
  /// Per group: quantized HF coefficients in YCbCr order (Y, Cb, Cr), each
  /// grid sized by the channel's JPEG upsampling shift.
  pass_groups : Array[FixedArray[@grid.Grid[Int32]]]
  /// `dequant_matrices.jpeg_quant_values(c)` for c = 0 (X), 1 (Y), 2 (B).
  jpeg_quant_values : Array[FixedArray[Int32]]
  /// DC offsets in YCbCr order.
  dc_offset : FixedArray[Int32]
}

///|
fn ParsedFrameData::jpeg_quant_values_of(
  self : ParsedFrameData,
  channel : Int32,
) -> FixedArray[Int32]? {
  if channel >= 0 && channel < self.jpeg_quant_values.length() {
    Some(self.jpeg_quant_values[channel])
  } else {
    None
  }
}

///|
const CFL_FIXED_POINT_BITS = 11

///|
const CFL_DEFAULT_COLOR_FACTOR = 84

///|
/// Integer chroma-from-luma, copied from libjxl.
///
/// `pass_groups` are in (Y, X, B) order; `x_from_y` / `b_from_y` are the
/// per-LF-group colour correlation grids (`hf_meta.x_from_y` / `b_from_y`).
pub fn integer_cfl(
  info : JpegFrameInfo,
  jpeg_quant_values : Array[FixedArray[Int32]],
  x_from_y : Array[@grid.Grid[Int32]],
  b_from_y : Array[@grid.Grid[Int32]],
  pass_groups : Array[FixedArray[@grid.Grid[Int32]]],
) -> Unit {
  let dequant_x = jpeg_quant_values[0]
  let dequant_y = jpeg_quant_values[1]
  let dequant_b = jpeg_quant_values[2]
  let n = dequant_y.length()
  let dequant_yx = FixedArray::make(n, 0)
  let dequant_yb = FixedArray::make(n, 0)
  for i in 0..<n {
    dequant_yx[i] = (1 << CFL_FIXED_POINT_BITS) * dequant_y[i] / dequant_x[i]
    dequant_yb[i] = (1 << CFL_FIXED_POINT_BITS) * dequant_y[i] / dequant_b[i]
  }
  let quant_ratio = [dequant_yx, dequant_yb]
  let groups_per_row = info.groups_per_row()
  for group_idx in 0..<pass_groups.length() {
    let pg = pass_groups[group_idx]
    let coeff_y = pg[0]
    let lf_group_idx = info.lf_group_idx_from_group_idx(group_idx)
    let group_x_in_lf = group_idx % groups_per_row % 8
    let group_y_in_lf = group_idx / groups_per_row % 8
    let cfl_x = group_x_in_lf * 4
    let cfl_y = group_y_in_lf * 4
    let xfy = x_from_y[lf_group_idx]
    let bfy = b_from_y[lf_group_idx]
    let cfl_x_end = if cfl_x + 4 < xfy.width() {
      cfl_x + 4
    } else {
      xfy.width()
    }
    let cfl_y_end = if cfl_y + 4 < xfy.height() {
      cfl_y + 4
    } else {
      xfy.height()
    }
    let cfl_factors = [
      xfy
      .as_subgrid()
      .subgrid(cfl_x, cfl_y, cfl_x_end - cfl_x, cfl_y_end - cfl_y),
      bfy
      .as_subgrid()
      .subgrid(cfl_x, cfl_y, cfl_x_end - cfl_x, cfl_y_end - cfl_y),
    ]
    let coeffs = [pg[1], pg[2]]
    let width = coeff_y.width()
    let height = coeff_y.height()
    let rounding_const = 1 << (CFL_FIXED_POINT_BITS - 1)
    for k in 0..<2 {
      let cfl_factor = cfl_factors[k]
      let coeff = coeffs[k]
      let quant_ratio = quant_ratio[k]
      for y in 0..<height {
        let cfl_y = y / 64
        let q_y = y % 8
        for x in 0..<width {
          let cfl_x = x / 64
          let factor = cfl_factor.get(cfl_x, cfl_y)
          let cy = coeff_y.get(x, y)
          // Dequant matrix is transposed.
          let q_x = x % 8
          let q = quant_ratio[q_y + 8 * q_x]
          let scale_factor = factor *
            (1 << CFL_FIXED_POINT_BITS) /
            CFL_DEFAULT_COLOR_FACTOR
          let q_scale = (q * scale_factor + rounding_const) >>
            CFL_FIXED_POINT_BITS
          let cfl = (cy * q_scale + rounding_const) >> CFL_FIXED_POINT_BITS
          coeff.set(x, y, coeff.get(x, y) + cfl)
        }
      }
    }
  }
}
