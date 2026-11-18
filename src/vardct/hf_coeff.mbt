// Port of jxl-vardct `hf_coeff.rs`.

///|
/// Parameters for decoding `HfCoeff`.
pub(all) struct HfCoeffParams {
  num_hf_presets : Int32
  hf_block_ctx : HfBlockContext
  block_info : @grid.SubGrid[BlockInfo]
  jpeg_upsampling : FixedArray[Int32]
  /// Quantized LF of the X, Y, B channels.
  lf_quant : FixedArray[@grid.SubGrid[Int32]]?
  hf_pass : HfPass
  coeff_shift : Int32
  tracker : @grid.AllocTracker?
}

///|
let coeff_freq_context : FixedArray[Int32] = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 15, 16, 16, 17, 17, 18, 18,
  19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 23, 23, 24, 24, 24, 24, 25, 25, 25, 25,
  26, 26, 26, 26, 27, 27, 27, 27, 28, 28, 28, 28, 29, 29, 29, 29, 30, 30, 30, 30,
]

///|
let coeff_num_nonzero_context : FixedArray[Int32] = [
  0, 31, 62, 62, 93, 93, 93, 93, 123, 123, 123, 123, 152, 152, 152, 152, 152, 152,
  152, 152, 180, 180, 180, 180, 180, 180, 180, 180, 180, 180, 180, 180, 206, 206,
  206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206,
  206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206, 206,
]

///|
/// Decode and write HF coefficients from the bitstream.
///
/// Coefficients are added to `hf_coeff_output` (X, Y, B), which must cover the
/// pass group.
pub fn write_hf_coeff(
  bitstream : @bitstream.Bitstream,
  params : HfCoeffParams,
  hf_coeff_output : FixedArray[@grid.SubGrid[Int32]],
) -> Unit raise @bitstream.JxlError {
  let num_hf_presets = params.num_hf_presets
  let block_info = params.block_info
  let dist = params.hf_pass.clone_decoder()
  let num_block_clusters = params.hf_block_ctx.num_block_clusters
  let upsampling_shifts = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(params.jpeg_upsampling, idx)
  })
  let hfp_bits = ceil_log2(num_hf_presets)
  let hfp = bitstream.read_bits(hfp_bits).reinterpret_as_int()
  if hfp >= num_hf_presets {
    raise @bitstream.ValidationFailed("selected HF preset out of bounds")
  }
  let ctx_size = 495 * num_block_clusters
  let cluster_map = FixedArray::make(ctx_size, 0)
  FixedArray::blit_to(
    dist.cluster_map(),
    cluster_map,
    len=ctx_size,
    src_offset=ctx_size * hfp,
  )
  dist.begin(bitstream)
  let width = block_info.width
  let height = block_info.height
  let non_zeros_grid_lengths = FixedArray::makei(3, c => {
    upsampling_shifts[c].shift_size((width, height)).0
  })
  let total_len = non_zeros_grid_lengths[0] +
    non_zeros_grid_lengths[1] +
    non_zeros_grid_lengths[2]
  // The allocation handle is dropped (and the bytes returned) when this
  // function returns, also on error.
  if params.tracker is Some(tracker) {
    tracker.alloc(total_len, 4)
  }
  defer (if params.tracker is Some(tracker) { tracker.free(total_len, 4) })
  write_hf_coeff_inner(
    bitstream, params, hf_coeff_output, dist, cluster_map, non_zeros_grid_lengths,
    upsampling_shifts,
  )
}

///|
fn write_hf_coeff_inner(
  bitstream : @bitstream.Bitstream,
  params : HfCoeffParams,
  hf_coeff_output : FixedArray[@grid.SubGrid[Int32]],
  dist : @coding.Decoder,
  cluster_map : FixedArray[Int32],
  non_zeros_grid_lengths : FixedArray[Int32],
  upsampling_shifts : FixedArray[@modular.ChannelShift],
) -> Unit raise @bitstream.JxlError {
  let block_info = params.block_info
  let hf_pass = params.hf_pass
  let coeff_shift = params.coeff_shift
  let lf_quant = params.lf_quant
  let qf_thresholds = params.hf_block_ctx.qf_thresholds
  let lf_thresholds = params.hf_block_ctx.lf_thresholds
  let block_ctx_map = params.hf_block_ctx.block_ctx_map
  let num_block_clusters = params.hf_block_ctx.num_block_clusters
  let lf_idx_mul = (lf_thresholds[0].length() + 1) *
    (lf_thresholds[1].length() + 1) *
    (lf_thresholds[2].length() + 1)
  let hf_idx_mul = qf_thresholds.length() + 1
  let hshifts = FixedArray::makei(3, i => upsampling_shifts[i].hshift())
  let vshifts = FixedArray::makei(3, i => upsampling_shifts[i].vshift())
  let width = block_info.width
  let height = block_info.height
  let non_zeros_grid_row = FixedArray::makei(3, c => {
    FixedArray::make(non_zeros_grid_lengths[c], 0)
  })
  let channel_order : FixedArray[Int32] = [1, 0, 2]
  let lf_channel_order : FixedArray[Int32] = [0, 2, 1]
  for y in 0..<height {
    for x in 0..<width {
      guard block_info.get(x, y) is Data(dct_select~, hf_mul=qf) else {
        continue
      }
      let (w8, h8) = dct_select.dct_select_size()
      let num_blocks = w8 * h8 // power of 2
      let num_blocks_log = num_blocks.ctz()
      let order_id = dct_select.order_id()
      let need_transpose = dct_select.need_transpose()
      let lf_idx = match lf_quant {
        Some(lf_quant) => {
          let mut idx = 0
          for c in lf_channel_order {
            let lf_thresholds = lf_thresholds[c]
            idx *= lf_thresholds.length() + 1
            let x = x >> hshifts[c]
            let y = y >> vshifts[c]
            let q = subgrid_get_checked(lf_quant[c], x, y)
            for threshold in lf_thresholds {
              if q > threshold {
                idx += 1
              }
            }
          }
          idx
        }
        None => 0
      }
      let hf_idx = {
        let mut idx = 0
        for threshold in qf_thresholds {
          if qf > threshold {
            idx += 1
          }
        }
        idx
      }
      for ci in 0..<3 {
        let ch_idx = ci * 13 + order_id
        let c = channel_order[ci] // y, x, b
        let hshift = hshifts[c]
        let vshift = vshifts[c]
        let sx = x >> hshift
        let sy = y >> vshift
        if hshift != 0 || vshift != 0 {
          if sx << hshift != x || sy << vshift != y {
            continue
          }
          if !(block_info.get(sx, sy) is Data(..)) {
            continue
          }
        }
        let idx = (ch_idx * hf_idx_mul + hf_idx) * lf_idx_mul + lf_idx
        let block_ctx = block_ctx_map[idx]
        let row = non_zeros_grid_row[c]
        let non_zeros_ctx = {
          let predicted = if sy == 0 {
            if sx == 0 {
              32
            } else {
              row[sx - 1]
            }
          } else if sx == 0 {
            row[sx]
          } else {
            (row[sx] + row[sx - 1] + 1) >> 1
          }
          let idx = if predicted >= 8 { 4 + predicted / 2 } else { predicted }
          block_ctx + idx * num_block_clusters
        }
        let mut non_zeros = dist
          .read_varint_with_multiplier_clustered(
            bitstream,
            cluster_map[non_zeros_ctx],
            0,
          )
          .reinterpret_as_int()
        if non_zeros < 0 || non_zeros > 63 << num_blocks_log {
          raise @bitstream.ValidationFailed("non_zeros too large")
        }
        let non_zeros_val = (non_zeros + num_blocks - 1) >> num_blocks_log
        for dx in 0..<w8 {
          row[sx + dx] = non_zeros_val
        }
        if non_zeros == 0 {
          continue
        }
        let coeff_grid = hf_coeff_output[c]
        let mut is_prev_coeff_nonzero = if non_zeros <= num_blocks * 4 {
          1
        } else {
          0
        }
        let order = hf_pass.order(order_id, c)
        let coeff_ctx_base = block_ctx * 458 + 37 * num_block_clusters
        for oi in num_blocks..<order.length() {
          let idx = oi - num_blocks
          let coeff_ctx = (
              coeff_num_nonzero_context[(non_zeros - 1) >> num_blocks_log] +
              coeff_freq_context[idx >> num_blocks_log]
            ) *
            2 +
            is_prev_coeff_nonzero
          if coeff_ctx >= 458 {
            raise @bitstream.ValidationFailed(
              "too many zeros in varblock HF coefficient",
            )
          }
          let cluster = cluster_map[coeff_ctx_base + coeff_ctx]
          let ucoeff = dist.read_varint_with_multiplier_clustered(
            bitstream, cluster, 0,
          )
          if ucoeff == 0 {
            is_prev_coeff_nonzero = 0
            continue
          }
          let coeff = @bitstream.unpack_signed(ucoeff) << coeff_shift
          let coeff_coord = order[oi]
          let mut dx = coeff_coord & 0xffff
          let mut dy = coeff_coord >> 16
          if need_transpose {
            let t = dx
            dx = dy
            dy = t
          }
          let x = sx * 8 + dx
          let y = sy * 8 + dy
          let v = subgrid_get_checked(coeff_grid, x, y)
          coeff_grid.set(x, y, v + coeff)
          is_prev_coeff_nonzero = 1
          non_zeros -= 1
          if non_zeros == 0 {
            break
          }
        }
      }
    }
  }
  dist.finalize()
}

///|
/// `SharedSubgrid::get` / `MutableSubgrid::get_mut`, which panic on
/// out-of-range coordinates.
fn subgrid_get_checked(g : @grid.SubGrid[Int32], x : Int32, y : Int32) -> Int32 {
  if x < 0 || y < 0 || x >= g.width || y >= g.height {
    abort("coordinate out of range: (\{x}, \{y}) not in \{g.width}x\{g.height}")
  }
  g.get(x, y)
}
