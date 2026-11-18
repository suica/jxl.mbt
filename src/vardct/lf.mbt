// Port of jxl-vardct `lf.rs`.

///|
/// Dequantization information for each channel.
#derive(Debug)
pub(all) struct LfChannelDequantization {
  all_default : Bool
  m_x_lf : Float
  m_y_lf : Float
  m_b_lf : Float
}

///|
pub fn LfChannelDequantization::default() -> LfChannelDequantization {
  {
    all_default: true,
    m_x_lf: 1.0 / 32.0,
    m_y_lf: 1.0 / 4.0,
    m_b_lf: 1.0 / 2.0,
  }
}

///|
pub fn LfChannelDequantization::parse(
  bitstream : @bitstream.Bitstream,
) -> LfChannelDequantization raise @bitstream.JxlError {
  let all_default = bitstream.read_bool()
  if all_default {
    return LfChannelDequantization::default()
  }
  let m_x_lf = bitstream.read_f16_as_f32()
  let m_y_lf = bitstream.read_f16_as_f32()
  let m_b_lf = bitstream.read_f16_as_f32()
  { all_default, m_x_lf, m_y_lf, m_b_lf, }
}

///|
pub fn LfChannelDequantization::m_x_lf_unscaled(
  self : LfChannelDequantization,
) -> Float {
  self.m_x_lf / 128.0
}

///|
pub fn LfChannelDequantization::m_y_lf_unscaled(
  self : LfChannelDequantization,
) -> Float {
  self.m_y_lf / 128.0
}

///|
pub fn LfChannelDequantization::m_b_lf_unscaled(
  self : LfChannelDequantization,
) -> Float {
  self.m_b_lf / 128.0
}

///|
/// Global quantizer multipliers.
#derive(Debug)
pub(all) struct Quantizer {
  global_scale : Int32
  quant_lf : Int32
}

///|
pub fn Quantizer::parse(
  bitstream : @bitstream.Bitstream,
) -> Quantizer raise @bitstream.JxlError {
  let global_scale = bitstream.read_u32(
    @bitstream.cu(1, 11),
    @bitstream.cu(2049, 11),
    @bitstream.cu(4097, 12),
    @bitstream.cu(8193, 16),
  )
  let quant_lf = bitstream.read_u32(
    @bitstream.c(16),
    @bitstream.cu(1, 5),
    @bitstream.cu(1, 8),
    @bitstream.cu(1, 16),
  )
  {
    global_scale: global_scale.reinterpret_as_int(),
    quant_lf: quant_lf.reinterpret_as_int(),
  }
}

///|
/// Channel correlation data, used by chroma-from-luma procedure.
#derive(Debug)
pub(all) struct LfChannelCorrelation {
  all_default : Bool
  colour_factor : Int32
  base_correlation_x : Float
  base_correlation_b : Float
  x_factor_lf : Int32
  b_factor_lf : Int32
}

///|
pub fn LfChannelCorrelation::default() -> LfChannelCorrelation {
  {
    all_default: true,
    colour_factor: 84,
    base_correlation_x: 0.0,
    base_correlation_b: 1.0,
    x_factor_lf: 128,
    b_factor_lf: 128,
  }
}

///|
pub fn LfChannelCorrelation::parse(
  bitstream : @bitstream.Bitstream,
) -> LfChannelCorrelation raise @bitstream.JxlError {
  let all_default = bitstream.read_bool()
  if all_default {
    return LfChannelCorrelation::default()
  }
  let colour_factor = bitstream
    .read_u32(
      @bitstream.c(84),
      @bitstream.c(256),
      @bitstream.cu(2, 8),
      @bitstream.cu(258, 16),
    )
    .reinterpret_as_int()
  let base_correlation_x = bitstream.read_f16_as_f32()
  let base_correlation_b = bitstream.read_f16_as_f32()
  let x_factor_lf = bitstream.read_bits(8).reinterpret_as_int()
  let b_factor_lf = bitstream.read_bits(8).reinterpret_as_int()
  {
    all_default,
    colour_factor,
    base_correlation_x,
    base_correlation_b,
    x_factor_lf,
    b_factor_lf,
  }
}

///|
/// Context information for the entropy decoder of HF coefficients.
#derive(Debug)
pub(all) struct HfBlockContext {
  qf_thresholds : Array[Int32]
  lf_thresholds : FixedArray[Array[Int32]]
  block_ctx_map : FixedArray[Int32]
  num_block_clusters : Int32
}

///|
pub fn HfBlockContext::default() -> HfBlockContext {
  {
    qf_thresholds: [],
    lf_thresholds: [[], [], []],
    block_ctx_map: [],
    num_block_clusters: 0,
  }
}

///|
pub fn HfBlockContext::parse(
  bitstream : @bitstream.Bitstream,
) -> HfBlockContext raise @bitstream.JxlError {
  let qf_thresholds = []
  let lf_thresholds : FixedArray[Array[Int32]] = [[], [], []]
  let (num_block_clusters, block_ctx_map) = if bitstream.read_bool() {
    let map : FixedArray[Int32] = [
      0, 1, 2, 2, 3, 3, 4, 5, 6, 6, 6, 6, 6, 7, 8, 9, 9, 10, 11, 12, 13, 14, 14,
      14, 14, 14, 7, 8, 9, 9, 10, 11, 12, 13, 14, 14, 14, 14, 14,
    ]
    (15, map)
  } else {
    let mut bsize = 1
    for thr in lf_thresholds {
      let num_lf_thresholds = bitstream.read_bits(4).reinterpret_as_int()
      bsize *= num_lf_thresholds + 1
      for _ in 0..<num_lf_thresholds {
        let t = bitstream.read_u32(
          @bitstream.u(4),
          @bitstream.cu(16, 8),
          @bitstream.cu(272, 16),
          @bitstream.cu(65808, 32),
        )
        thr.push(@bitstream.unpack_signed(t))
      }
    }
    let num_qf_thresholds = bitstream.read_bits(4).reinterpret_as_int()
    bsize *= num_qf_thresholds + 1
    for _ in 0..<num_qf_thresholds {
      let t = bitstream.read_u32(
        @bitstream.u(2),
        @bitstream.cu(4, 3),
        @bitstream.cu(12, 5),
        @bitstream.cu(44, 8),
      )
      qf_thresholds.push(1 + t.reinterpret_as_int())
    }
    @coding.read_clusters(bitstream, bsize * 39)
  }
  { qf_thresholds, lf_thresholds, block_ctx_map, num_block_clusters, }
}

///|
/// Paramters for decoding `LfCoeff`.
pub(all) struct LfCoeffParams {
  lf_group_idx : Int32
  lf_width : Int32
  lf_height : Int32
  jpeg_upsampling : FixedArray[Int32]
  bits_per_sample : Int32
  global_ma_config : @modular.MaConfig?
  allow_partial : Bool
  tracker : @grid.AllocTracker?
}

///|
/// Quantized LF image.
pub(all) struct LfCoeff {
  extra_precision : Int32
  lf_quant : @modular.Modular
  partial : Bool
}

///|
pub fn LfCoeff::parse(
  bitstream : @bitstream.Bitstream,
  params : LfCoeffParams,
) -> LfCoeff raise @bitstream.JxlError {
  let extra_precision = bitstream.read_bits(2).reinterpret_as_int()
  let width = (params.lf_width + 7) / 8
  let height = (params.lf_height + 7) / 8
  let channel_shifts = [1, 0, 2].map(idx => {
    @modular.ChannelShift::from_jpeg_upsampling(params.jpeg_upsampling, idx)
  })
  let lf_quant_params = @modular.ModularParams::new(
    width,
    height,
    0,
    params.bits_per_sample,
    channel_shifts,
    params.global_ma_config,
    params.tracker,
  )
  let lf_quant = @modular.Modular::parse(bitstream, lf_quant_params)
  let image = lf_quant.image_mut().unwrap()
  let subimage = image.prepare_subimage()
  subimage.decode(bitstream, 1 + params.lf_group_idx, params.allow_partial)
  let complete = subimage.finish(@threadpool.JxlThreadPool::none())
  { extra_precision, lf_quant, partial: !complete, }
}
