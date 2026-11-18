// Port of jxl-vardct `hf_metadata.rs`.

///|
/// Parameters for decoding `HfMetadata`.
pub(all) struct HfMetadataParams {
  num_lf_groups : Int32
  lf_group_idx : Int32
  lf_width : Int32
  lf_height : Int32
  jpeg_upsampling : FixedArray[Int32]
  bits_per_sample : Int32
  global_ma_config : @modular.MaConfig?
  /// `(quant_mul, sharp_lut)`
  epf : (Float, FixedArray[Float])?
  quantizer_global_scale : Int32
  tracker : @grid.AllocTracker?
  pool : @threadpool.JxlThreadPool
}

///|
/// Data for decoding and rendering varblocks within an LF group.
pub(all) struct HfMetadata {
  /// Chroma-from-luma correlation grid for X channel.
  x_from_y : @grid.Grid[Int32]
  /// Chroma-from-luma correlation grid for B channel.
  b_from_y : @grid.Grid[Int32]
  /// Varblock information in an LF group.
  block_info : @grid.Grid[BlockInfo]
  /// Sigma parameter grid for edge-preserving filter.
  epf_sigma : @grid.Grid[Float]
}

///|
/// Varblock grid information.
#derive(Eq, Debug)
pub(all) enum BlockInfo {
  /// The block is not initialized yet.
  Uninit
  /// The block is occupied by a varblock.
  Occupied
  /// The block is the top-left block of a varblock.
  Data(dct_select~ : TransformType, hf_mul~ : Int32)
}

///|
pub impl Default for BlockInfo with fn default() {
  Uninit
}

///|
fn BlockInfo::is_occupied(self : BlockInfo) -> Bool {
  !(self is Uninit)
}

///|
/// `ceil(log2(n))` for `n >= 1` (`n.next_power_of_two().trailing_zeros()`).
fn ceil_log2(n : Int32) -> Int32 {
  if n <= 1 {
    0
  } else {
    32 - (n - 1).clz()
  }
}

///|
pub fn HfMetadata::parse(
  bitstream : @bitstream.Bitstream,
  params : HfMetadataParams,
) -> HfMetadata raise @bitstream.JxlError {
  let lf_width = params.lf_width
  let lf_height = params.lf_height
  let jpeg_upsampling = params.jpeg_upsampling
  let mut bw = (lf_width + 7) / 8
  let mut bh = (lf_height + 7) / 8
  let h_upsample = jpeg_upsampling.iter().any(j => j == 1 || j == 2)
  let v_upsample = jpeg_upsampling.iter().any(j => j == 1 || j == 3)
  if h_upsample {
    bw = (bw + 1) / 2 * 2
  }
  if v_upsample {
    bh = (bh + 1) / 2 * 2
  }
  let nb_blocks = 1 +
    bitstream.read_bits(ceil_log2(bw * bh)).reinterpret_as_int()
  let channels = [
    @modular.ModularChannelParams::new(
      (lf_width + 63) / 64,
      (lf_height + 63) / 64,
    ),
    @modular.ModularChannelParams::new(
      (lf_width + 63) / 64,
      (lf_height + 63) / 64,
    ),
    @modular.ModularChannelParams::new(nb_blocks, 2),
    @modular.ModularChannelParams::new(bw, bh),
  ]
  let modular_params = @modular.ModularParams::with_channels(
    0,
    params.bits_per_sample,
    channels,
    params.global_ma_config,
    params.tracker,
  )
  let modular = @modular.Modular::parse(bitstream, modular_params)
  let image = modular.image_mut().unwrap()
  let subimage = image.prepare_subimage()
  subimage.decode(
    bitstream,
    1 + 2 * params.num_lf_groups + params.lf_group_idx,
    false,
  )
  // `subimage.finish(pool)` (sequential, as upstream with `JxlThreadPool::none()`)
  ignore(params.pool)
  ignore(subimage.finish())
  let image = modular.into_image().unwrap().into_image_channels()
  let x_from_y = image[0]
  let b_from_y = image[1]
  let block_info_raw = image[2]
  let sharpness = image[3].buf()
  let epf_sigma = @grid.Grid::with_alloc_tracker(
    bw,
    bh,
    (0.0 : Float),
    params.tracker,
  )
  let epf_sigma_buf = epf_sigma.buf()
  let epf = match params.epf {
    Some((quant_mul, sharp_lut)) =>
      Some(
        (
          quant_mul * 65536.0 / Float::from_int(params.quantizer_global_scale),
          sharp_lut,
        ),
      )
    None => None
  }
  let block_info = @grid.Grid::with_alloc_tracker(
    bw,
    bh,
    BlockInfo::Uninit,
    params.tracker,
    elem_size=8,
  )
  let mut y = 0
  let mut data_idx = 0
  while y < bh {
    let mut x = 0
    while x < bw {
      if !block_info.get(x, y).is_occupied() {
        guard data_idx < block_info_raw.width() && block_info_raw.height() > 0 else {
          raise @bitstream.ValidationFailed("BlockInfo doesn't fill LF group")
        }
        let dct_select = TransformType::try_from(
          block_info_raw.get(data_idx, 0) & 0xff,
        )
        let mul = block_info_raw.get(data_idx, 1)
        let hf_mul = mul + 1
        if hf_mul <= 0 {
          raise @bitstream.ValidationFailed("non-positive HfMul")
        }
        let (dw, dh) = dct_select.dct_select_size()
        let x_in_group = x % 32
        let y_in_group = y % 32
        if x_in_group + dw > 32 || y_in_group + dh > 32 {
          raise @bitstream.ValidationFailed(
            "varblock is placed across pass group border",
          )
        }
        let epf = match epf {
          Some((quant_mul, sharp_lut)) =>
            Some((quant_mul / Float::from_int(hf_mul), sharp_lut))
          None => None
        }
        for dy in 0..<dh {
          for dx in 0..<dw {
            if x + dx < bw && y + dy < bh {
              if block_info.get(x + dx, y + dy).is_occupied() {
                raise @bitstream.ValidationFailed("varblocks overlap")
              }
            } else {
              raise @bitstream.ValidationFailed(
                "varblock doesn't fit in an LF group",
              )
            }
            block_info.set(
              x + dx,
              y + dy,
              if dx == 0 && dy == 0 {
                Data(dct_select~, hf_mul~)
              } else {
                Occupied
              },
            )
            if epf is Some((sigma, sharp_lut)) {
              let sharpness = sharpness[(y + dy) * bw + (x + dx)]
              if sharpness < 0 || sharpness >= 8 {
                raise @bitstream.ValidationFailed("invalid EPF sharpness value")
              }
              let sigma = sigma * sharp_lut[sharpness]
              epf_sigma_buf[(y + dy) * bw + (x + dx)] = sigma
            }
          }
        }
        data_idx += 1
        x += dw
      } else {
        x += 1
      }
    }
    y += 1
  }
  { x_from_y, b_from_y, block_info, epf_sigma, }
}
