// Port of jxl-vardct `dequant.rs`.

///|
/// Parameters of a dequantization matrix, as encoded in the bitstream.
/// All arrays are indexed by channel first (X, Y, B).
enum DequantMatrixParamsEncoding {
  Hornuss(FixedArray[FixedArray[Float]])
  Dct2(FixedArray[FixedArray[Float]])
  Dct4(
    params~ : FixedArray[FixedArray[Float]],
    dct_params~ : FixedArray[FixedArray[Float]],
  )
  Dct4x8(
    params~ : FixedArray[FixedArray[Float]],
    dct_params~ : FixedArray[FixedArray[Float]],
  )
  Afv(
    params~ : FixedArray[FixedArray[Float]],
    dct_params~ : FixedArray[FixedArray[Float]],
    dct4x4_params~ : FixedArray[FixedArray[Float]],
  )
  Dct(FixedArray[FixedArray[Float]])
  /// `params` holds the decoded channels of the Modular image (row-major,
  /// `dequant_matrix_size` samples each).
  Raw(denominator~ : Float, params~ : FixedArray[FixedArray[Int32]])
}

///|
struct DequantMatrixParams {
  dct_select : TransformType
  encoding : DequantMatrixParamsEncoding
}

///|
let seq_a : FixedArray[Float] = [
  -1.025, -0.78, -0.65012, -0.19041574, -0.20819396, -0.421064, -0.32733846,
]

///|
let seq_b : FixedArray[Float] = [
  -0.30419582, -0.36330363, -0.3566038, -0.34430745, -0.33699593, -0.30180866, -0.27321684,
]

///|
let seq_c : FixedArray[Float] = [-1.2, -1.2, -0.8, -0.7, -0.7, -0.4, -0.5]

///|
fn dct4x8_default_params() -> FixedArray[FixedArray[Float]] {
  [
    [2198.0505, -0.96269625, -0.7619425, -0.65511405],
    [764.36554, -0.926302, -0.967523, -0.2784529],
    [527.10754, -1.4594386, -1.4500821, -1.5843723],
  ]
}

///|
fn dct4_default_params() -> FixedArray[FixedArray[Float]] {
  [[2200.0, 0.0, 0.0, 0.0], [392.0, 0.0, 0.0, 0.0], [112.0, -0.25, -0.25, -0.5]]
}

///|
fn prepend(first : Float, rest : FixedArray[Float]) -> FixedArray[Float] {
  let out = FixedArray::make(rest.length() + 1, first)
  FixedArray::blit_to(rest, out, len=rest.length(), dst_offset=1)
  out
}

///|
fn DequantMatrixParamsEncoding::make_dct_param_common_seq(
  a : Float,
  b : Float,
  c : Float,
) -> DequantMatrixParamsEncoding {
  Dct([prepend(a, seq_a), prepend(b, seq_b), prepend(c, seq_c)])
}

///|
fn DequantMatrixParamsEncoding::default_with(
  dct_select : TransformType,
) -> DequantMatrixParamsEncoding {
  match dct_select {
    Dct8 =>
      Dct([
        [3150.0, 0.0, -0.4, -0.4, -0.4, -2.0],
        [560.0, 0.0, -0.3, -0.3, -0.3, -0.3],
        [512.0, -2.0, -1.0, 0.0, -1.0, -2.0],
      ])
    Hornuss =>
      Hornuss([
        [280.0, 3160.0, 3160.0],
        [60.0, 864.0, 864.0],
        [18.0, 200.0, 200.0],
      ])
    Dct2 =>
      Dct2([
        [3840.0, 2560.0, 1280.0, 640.0, 480.0, 300.0],
        [960.0, 640.0, 320.0, 180.0, 140.0, 120.0],
        [640.0, 320.0, 128.0, 64.0, 32.0, 16.0],
      ])
    Dct4 =>
      Dct4(
        params=[[1.0, 1.0], [1.0, 1.0], [1.0, 1.0]],
        dct_params=dct4_default_params(),
      )
    Dct16 =>
      Dct([
        [
          8996.873, -1.3000778, -0.4942453, -0.43909377, -0.6350102, -0.9017726,
          -1.6162099,
        ],
        [
          3191.4836, -0.67424583, -0.80745816, -0.4492584, -0.3586544, -0.3132239,
          -0.37615025,
        ],
        [
          1157.504, -2.0531423, -1.4, -0.5068713, -0.4270873, -1.4856834, -4.920914,
        ],
      ])
    Dct32 =>
      Dct([
        [15718.408, -1.025, -0.98, -0.9012, -0.4, -0.48819396, -0.421064, -0.27],
        [
          7305.7637, -0.8041958, -0.76330364, -0.5566038, -0.49785304, -0.43699592,
          -0.40180868, -0.27321684,
        ],
        [
          3803.5317, -3.0607336, -2.041327, -2.023565, -0.54953897, -0.4, -0.4, -0.3,
        ],
      ])
    Dct8x16 | Dct16x8 =>
      Dct([
        [7240.7734, -0.7, -0.7, -0.2, -0.2, -0.2, -0.5],
        [1448.1547, -0.5, -0.5, -0.5, -0.2, -0.2, -0.2],
        [506.85413, -1.4, -0.2, -0.5, -0.5, -1.5, -3.6],
      ])
    Dct8x32 | Dct32x8 =>
      Dct([
        [
          16283.249, -1.7812846, -1.6309059, -1.0382179, -0.85, -0.7, -0.9, -1.2360638,
        ],
        [5089.1577, -0.3200494, -0.3536285, -0.3034, -0.61, -0.5, -0.5, -0.6],
        [
          3397.7761, -0.32132736, -0.3450762, -0.7034, -0.9, -1.0, -1.0, -1.1754606,
        ],
      ])
    Dct16x32 | Dct32x16 =>
      Dct([
        [
          13844.971, -0.971138, -0.658, -0.42026, -0.22712, -0.2206, -0.226, -0.6,
        ],
        [
          4798.964, -0.6112531, -0.8377079, -0.7901486, -0.26927274, -0.38272768,
          -0.22924222, -0.20719099,
        ],
        [1807.2369, -1.2, -1.2, -0.7, -0.7, -0.7, -0.4, -0.5],
      ])
    Dct4x8 | Dct8x4 =>
      Dct4x8(params=[[1.0], [1.0], [1.0]], dct_params=dct4x8_default_params())
    Afv0 | Afv1 | Afv2 | Afv3 =>
      Afv(
        params=[
          [3072.0, 3072.0, 256.0, 256.0, 256.0, 414.0, 0.0, 0.0, 0.0],
          [1024.0, 1024.0, 50.0, 50.0, 50.0, 58.0, 0.0, 0.0, 0.0],
          [384.0, 384.0, 12.0, 12.0, 12.0, 22.0, -0.25, -0.25, -0.25],
        ],
        dct_params=dct4x8_default_params(),
        dct4x4_params=dct4_default_params(),
      )
    Dct64 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        23966.166, 8380.191, 4493.024,
      )
    Dct32x64 | Dct64x32 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        15358.898, 5597.3604, 2919.9617,
      )
    Dct128 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        47932.332, 16760.383, 8986.048,
      )
    Dct64x128 | Dct128x64 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        30717.797, 11194.721, 5839.9233,
      )
    Dct256 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        95864.664, 33520.766, 17972.096,
      )
    Dct128x256 | Dct256x128 =>
      DequantMatrixParamsEncoding::make_dct_param_common_seq(
        61435.594, 24209.441, 12979.847,
      )
  }
}

///|
fn DequantMatrixParams::default_with(
  dct_select : TransformType,
) -> DequantMatrixParams {
  {
    dct_select,
    encoding: DequantMatrixParamsEncoding::default_with(dct_select),
  }
}

///|
/// `f32::powf`. Computed in double precision and rounded once, which agrees
/// with libm's `powf` up to 1 ulp.
fn powf_f32(base : Float, exp : Float) -> Float {
  powf(base, exp)
}

///|
fn interpolate(pos : Float, max : Float, bands : FixedArray[Float]) -> Float {
  let len = bands.length()
  guard len > 0 && pos >= 0.0 && max > 0.0 else {
    abort("interpolate: invalid arguments")
  }
  if len == 1 {
    return bands[0]
  }
  let scaled_pos = pos * Float::from_int(len - 1) / max
  let scaled_index = scaled_pos.to_int() // scaled_pos >= 0.0
  let frac_index = scaled_pos - Float::from_int(scaled_index)
  let a = bands[scaled_index]
  let b = bands[scaled_index + 1]
  a * powf_f32(b / a, frac_index)
}

///|
fn mult(x : Float) -> Float {
  if x > 0.0 {
    1.0 + x
  } else {
    1.0 / (1.0 - x)
  }
}

///|
let sqrt_2_plus_eps : Float = sqrt_2_f32 + 1.0e-6

///|
fn dct_quant_weights(
  params : FixedArray[Float],
  width : Int32,
  height : Int32,
) -> FixedArray[Float] raise @bitstream.JxlError {
  let bands = FixedArray::make(params.length(), (0.0 : Float))
  let mut last_band = params[0]
  bands[0] = last_band
  for i in 1..<params.length() {
    let band = last_band * mult(params[i])
    if band <= 0.0 {
      raise @bitstream.ValidationFailed("DCT dequant matrix: band <= 0")
    }
    bands[i] = band
    last_band = band
  }
  let ret = FixedArray::make(height * width, (0.0 : Float))
  let wm1 = Float::from_int(width - 1)
  let hm1 = Float::from_int(height - 1)
  for y in 0..<height {
    for x in 0..<width {
      let dx = Float::from_int(x) / wm1
      let dy = Float::from_int(y) / hm1
      let distance = (dx * dx + dy * dy).sqrt()
      ret[y * width + x] = interpolate(distance, sqrt_2_plus_eps, bands)
    }
  }
  ret
}

///|
let afv_freqs : FixedArray[Float] = [
  0.0, 0.0, 0.8517779, 5.3777843, 0.0, 0.0, 4.734748, 5.4492455, 1.659827, 4.0, 7.275749,
  10.423227, 2.6629324, 7.6306577, 8.962389, 12.971662,
]

///|
fn DequantMatrixParams::into_matrix(
  self : DequantMatrixParams,
) -> FixedArray[FixedArray[Float]] raise @bitstream.JxlError {
  let dct_select = self.dct_select
  let need_recip = !(self.encoding is Raw(_))
  let weights : FixedArray[FixedArray[Float]] = match self.encoding {
    Dct(dct_params) => {
      let (width, height) = dct_select.dequant_matrix_size()
      [
        dct_quant_weights(dct_params[0], width, height),
        dct_quant_weights(dct_params[1], width, height),
        dct_quant_weights(dct_params[2], width, height),
      ]
    }
    Hornuss(params) =>
      FixedArray::makei(3, c => {
        let params = params[c]
        let ret = FixedArray::make(64, params[0])
        ret[0] = 1.0
        ret[1] = params[1]
        ret[8] = params[1]
        ret[9] = params[2]
        ret
      })
    Dct2(params) =>
      FixedArray::makei(3, c => {
        let params = params[c]
        let ret = FixedArray::make(64, (0.0 : Float))
        ret[0] = 1.0
        for idx in 0..<6 {
          let val = params[idx]
          let shift = idx / 2
          let dim = 1 << shift
          if idx % 2 == 0 {
            for y in 0..<dim {
              for x in dim..<(dim * 2) {
                ret[y * 8 + x] = val
                ret[x * 8 + y] = val
              }
            }
          } else {
            for y in dim..<(dim * 2) {
              for x in dim..<(dim * 2) {
                ret[y * 8 + x] = val
              }
            }
          }
        }
        ret
      })
    Dct4(params~, dct_params~) => {
      let out = FixedArray::make(3, FixedArray::make(0, (0.0 : Float)))
      for c in 0..<3 {
        let params = params[c]
        let mat = dct_quant_weights(dct_params[c], 4, 4)
        let ret = FixedArray::make(64, (0.0 : Float))
        for y in 0..<4 {
          for x in 0..<4 {
            let v = mat[y * 4 + x]
            ret[y * 16 + x * 2] = v
            ret[y * 16 + x * 2 + 1] = v
            ret[(y * 2 + 1) * 8 + x * 2] = v
            ret[(y * 2 + 1) * 8 + x * 2 + 1] = v
          }
        }
        ret[1] = ret[1] / params[0]
        ret[8] = ret[8] / params[0]
        ret[9] = ret[9] / params[1]
        out[c] = ret
      }
      out
    }
    Dct4x8(params~, dct_params~) => {
      let out = FixedArray::make(3, FixedArray::make(0, (0.0 : Float)))
      for c in 0..<3 {
        let params = params[c]
        let mat = dct_quant_weights(dct_params[c], 8, 4)
        let ret = FixedArray::make(64, (0.0 : Float))
        for y in 0..<4 {
          FixedArray::blit_to(
            mat,
            ret,
            len=8,
            src_offset=y * 8,
            dst_offset=y * 16,
          )
          FixedArray::blit_to(
            mat,
            ret,
            len=8,
            src_offset=y * 8,
            dst_offset=y * 16 + 8,
          )
        }
        ret[8] = ret[8] / params[0]
        out[c] = ret
      }
      out
    }
    Afv(params~, dct_params~, dct4x4_params~) => {
      let freq_lo = afv_freqs[2]
      let freq_hi = afv_freqs[15]
      let out = FixedArray::make(3, FixedArray::make(0, (0.0 : Float)))
      for c in 0..<3 {
        let params = params[c]
        let weights_4x8 = dct_quant_weights(dct_params[c], 8, 4)
        let weights_4x4 = dct_quant_weights(dct4x4_params[c], 4, 4)
        let bands : FixedArray[Float] = [params[5], 0.0, 0.0, 0.0]
        let mut prev_band = bands[0]
        for i in 1..<4 {
          bands[i] = prev_band * mult(params[5 + i])
          prev_band = bands[i]
        }
        let ret = FixedArray::make(64, (0.0 : Float))
        for y in 0..<4 {
          for x in 0..<4 {
            ret[16 * y + 2 * x] = match (x, y) {
              (0, 0) => 1.0
              (0, 1) => params[2]
              (1, 0) => params[3]
              (1, 1) => params[4]
              (x, y) =>
                interpolate(
                  afv_freqs[y * 4 + x] - freq_lo,
                  freq_hi - freq_lo + 1.0e-6,
                  bands,
                )
            }
          }
        }
        for y in 0..<4 {
          for x in 0..<8 {
            ret[16 * y + 8 + x] = if y == 0 && x == 0 {
              params[0]
            } else {
              weights_4x8[y * 8 + x]
            }
          }
          for x in 0..<4 {
            ret[16 * y + 2 * x + 1] = if y == 0 && x == 0 {
              params[1]
            } else {
              weights_4x4[y * 4 + x]
            }
          }
        }
        out[c] = ret
      }
      out
    }
    Raw(denominator~, params~) => {
      let (width, height) = dct_select.dequant_matrix_size()
      FixedArray::makei(3, c => {
        let channel = params[c]
        let ret = FixedArray::make(width * height, (0.0 : Float))
        let n = if channel.length() < ret.length() {
          channel.length()
        } else {
          ret.length()
        }
        for i in 0..<n {
          ret[i] = Float::from_int(channel[i]) * denominator
        }
        ret
      })
    }
  }
  if need_recip {
    for w in weights {
      for i in 0..<w.length() {
        w[i] = (1.0 : Float) / w[i]
      }
    }
  }
  for w in weights {
    for v in w {
      if v >= 1.0e8 || v <= 0.0 {
        raise @bitstream.ValidationFailed(
          "Dequant matrix has too large or non-positive element",
        )
      }
    }
  }
  weights
}

///|
fn read_fixed(
  bitstream : @bitstream.Bitstream,
  n : Int32,
) -> FixedArray[FixedArray[Float]] raise @bitstream.JxlError {
  let out = FixedArray::make(3, FixedArray::make(0, (0.0 : Float)))
  for c in 0..<3 {
    let row = FixedArray::make(n, (0.0 : Float))
    for i in 0..<n {
      row[i] = bitstream.read_f16_as_f32()
    }
    out[c] = row
  }
  out
}

///|
fn read_dct_params(
  bitstream : @bitstream.Bitstream,
) -> FixedArray[FixedArray[Float]] raise @bitstream.JxlError {
  let num_params = bitstream.read_bits(4).reinterpret_as_int() + 1
  let params = read_fixed(bitstream, num_params)
  for c in 0..<3 {
    params[c][0] = params[c][0] * 64.0
  }
  params
}

///|
/// Parses the parameters of one dequantization matrix.
/// `decode_raw` decodes the Modular-encoded matrix of encoding mode 7.
fn DequantMatrixParams::parse(
  bitstream : @bitstream.Bitstream,
  params : DequantMatrixSetParams,
) -> DequantMatrixParams raise @bitstream.JxlError {
  let dct_select = params.dct_select
  let encoding_mode = bitstream.read_bits(3).reinterpret_as_int()
  if encoding_mode >= 1 && encoding_mode <= 5 {
    match dct_select.dequant_matrix_param_index() {
      0 | 1 | 2 | 3 | 9 | 10 => ()
      _ =>
        raise @bitstream.ValidationFailed(
          "invalid encoding mode for DctSelect value",
        )
    }
  }
  let encoding : DequantMatrixParamsEncoding = match encoding_mode {
    0 => DequantMatrixParamsEncoding::default_with(dct_select)
    1 => Hornuss(read_fixed(bitstream, 3))
    2 => Dct2(read_fixed(bitstream, 6))
    3 => {
      let params = read_fixed(bitstream, 2)
      let dct_params = read_dct_params(bitstream)
      Dct4(params~, dct_params~)
    }
    4 => {
      let params = read_fixed(bitstream, 1)
      let dct_params = read_dct_params(bitstream)
      Dct4x8(params~, dct_params~)
    }
    5 => {
      let params = read_fixed(bitstream, 9)
      for c in 0..<3 {
        for i in 0..<6 {
          params[c][i] = params[c][i] * 64.0
        }
      }
      let dct_params = read_dct_params(bitstream)
      let dct4x4_params = read_dct_params(bitstream)
      Afv(params~, dct_params~, dct4x4_params~)
    }
    6 => Dct(read_dct_params(bitstream))
    7 => {
      let (width, height) = dct_select.dequant_matrix_size()
      let denominator = bitstream.read_f16_as_f32()
      let channels = decode_raw_dequant_matrix(bitstream, width, height, params)
      Raw(denominator~, params=channels)
    }
    _ => abort("unreachable")
  }
  { dct_select, encoding, }
}

///|
/// A set of dequantization matrices.
pub struct DequantMatrixSet {
  priv matrices : FixedArray[FixedArray[FixedArray[Float]]]
  priv matrices_tr : FixedArray[FixedArray[FixedArray[Float]]]
  priv jpeg_matrices : FixedArray[FixedArray[Int32]]
}

///|
let dct_select_list : FixedArray[TransformType] = [
  Dct8,
  Hornuss,
  Dct2,
  Dct4,
  Dct16,
  Dct32,
  Dct8x16,
  Dct8x32,
  Dct16x32,
  Dct4x8,
  Afv0,
  Dct64,
  Dct32x64,
  Dct128,
  Dct64x128,
  Dct256,
  Dct128x256,
]

///|
pub fn DequantMatrixSet::parse(
  bitstream : @bitstream.Bitstream,
  params : DequantMatrixSetParams,
) -> DequantMatrixSet raise @bitstream.JxlError {
  let param_list : Array[DequantMatrixParams] = []
  if bitstream.read_bool() {
    for dct_select in dct_select_list {
      param_list.push(DequantMatrixParams::default_with(dct_select))
    }
  } else {
    for idx, dct_select in dct_select_list {
      let local_params = {
        ..params,
        dct_select,
        stream_index: params.stream_index + idx,
      }
      param_list.push(DequantMatrixParams::parse(bitstream, local_params))
    }
  }
  let jpeg_matrices = match param_list[0].encoding {
    Raw(denominator~, params~) if ((1.0 : Float) / denominator).round().to_int() ==
      2040 => params.map(ch => ch.copy())
    _ => []
  }
  let matrices = FixedArray::makei(dct_select_list.length(), _ => {
    FixedArray::make(0, FixedArray::make(0, (0.0 : Float)))
  })
  for idx, p in param_list {
    matrices[idx] = p.into_matrix()
  }
  let matrices_tr = FixedArray::makei(dct_select_list.length(), i => {
    let (width, height) = dct_select_list[i].dequant_matrix_size()
    FixedArray::makei(3, c => {
      let matrix = matrices[i][c]
      FixedArray::makei(matrix.length(), idx => {
        let mat_x = idx % height
        let mat_y = idx / height
        matrix[mat_x * width + mat_y]
      })
    })
  })
  { matrices, matrices_tr, jpeg_matrices, }
}

///|
/// Returns the dequantization matrix for the given channel and transform type.
///
/// The coefficients is in the raster order.
pub fn DequantMatrixSet::get(
  self : DequantMatrixSet,
  channel : Int32,
  dct_select : TransformType,
) -> FixedArray[Float] {
  self.matrices[dct_select.dequant_matrix_param_index()][channel]
}

///|
/// Returns the transposed dequantization matrix for the given channel and transform type.
///
/// The coefficients is in the raster order.
pub fn DequantMatrixSet::get_transposed(
  self : DequantMatrixSet,
  channel : Int32,
  dct_select : TransformType,
) -> FixedArray[Float] {
  self.matrices_tr[dct_select.dequant_matrix_param_index()][channel]
}

///|
pub fn DequantMatrixSet::jpeg_quant_values(
  self : DequantMatrixSet,
  channel : Int32,
) -> FixedArray[Int32]? {
  if channel >= 0 && channel < self.jpeg_matrices.length() {
    Some(self.jpeg_matrices[channel])
  } else {
    None
  }
}
