// Port of jxl-render filter/epf.rs and filter/impls/generic/epf.rs
// (edge-preserving filter). Only the generic (scalar) row handler is ported;
// rows run sequentially (the `JxlThreadPool::None` path).

///|
/// Plain-value form of `jxl_frame::filter::EpfParams` used by the filter
/// kernels (`sharp_lut` and `quant_mul` are only used when computing sigma,
/// which happens in vardct).
pub(all) struct EpfKernelParams {
  iters : Int32
  channel_scale : FixedArray[Float]
  pass0_sigma_scale : Float
  pass2_sigma_scale : Float
  border_sad_mul : Float
  sigma_for_modular : Float
}

///|
/// Runs every EPF pass on the colour views `fb` (already cut to
/// `color_padded_region`), using `fb_scratch_arr` (same sizes) as the second
/// buffer. Returns `true` when the final result is in `fb_scratch_arr`
/// (`iters` is 1 or 3), which upstream then puts into the image with
/// `replace_channel`; otherwise the result is in `fb`.
///
/// `region_left`/`region_top`/`region_width`/`region_height` describe
/// `color_padded_region`; `sigma_grid_map[lf_group_idx]` is the
/// `hf_meta.epf_sigma` grid of the LF group, if any.
pub fn apply_epf_grids(
  fb : Array[@grid.SubGrid[Float]],
  fb_scratch_arr : Array[@grid.Grid[Float]],
  region_left : Int32,
  region_top : Int32,
  region_width : Int32,
  region_height : Int32,
  group_dim : Int32,
  lf_groups_per_row : Int32,
  sigma_grid_map : Array[@grid.Grid[Float]?],
  epf_params : EpfKernelParams,
) -> Bool {
  let iters = epf_params.iters
  let mut fb = fb
  let mut fb_scratch = fb_scratch_arr.map(fn(g) { g.as_subgrid() })
  let run = fn(step : Int32, input, output) {
    epf_step(
      step, input, output, region_left, region_top, region_width, region_height,
      group_dim, lf_groups_per_row, sigma_grid_map, epf_params,
    )
  }
  // Step 0
  if iters == 3 {
    run(0, fb, fb_scratch)
    let t = fb
    fb = fb_scratch
    fb_scratch = t
  }
  // Step 1
  {
    run(1, fb, fb_scratch)
    let t = fb
    fb = fb_scratch
    fb_scratch = t
  }
  // Step 2
  if iters >= 2 {
    run(2, fb, fb_scratch)
    let t = fb
    fb = fb_scratch
    fb_scratch = t
  }
  iters == 1 || iters == 3
}

///|
/// One EPF pass (`impls::epf::<STEP>` → `run_epf_rows` → `epf_row::<STEP>`),
/// reading `input` and writing `output`.
pub fn epf_step(
  step : Int32,
  input : Array[@grid.SubGrid[Float]],
  output : Array[@grid.SubGrid[Float]],
  left : Int32,
  top : Int32,
  width : Int32,
  height : Int32,
  group_dim : Int32,
  lf_groups_per_row : Int32,
  sigma_grid_map : Array[@grid.Grid[Float]?],
  epf_params : EpfKernelParams,
) -> Unit {
  guard left >= 0 && top >= 0 && left % 8 == 0 && top % 8 == 0 else {
    abort("epf: region is not aligned")
  }
  let sigma_group_dim_shift = group_dim.ctz()
  let sigma_group_dim_mask = group_dim - 1
  let groups_per_row = lf_groups_per_row
  let sigma_len = (width + 7) / 8
  // The per-thread state of `for_each_vec_with`; with no thread pool it is
  // shared by all jobs, in order.
  let sigma_row = FixedArray::make(sigma_len, epf_params.sigma_for_modular)
  let input_rows = FixedArray::make(21, 0)
  let mut base_y = 0
  while base_y < height {
    let job_height = if height - base_y < 8 { height - base_y } else { 8 }
    let sigma_y = (top + base_y) / 8
    let sigma_group_y = sigma_y >> sigma_group_dim_shift
    let sigma_inner_y = sigma_y & sigma_group_dim_mask
    for dx in 0..<sigma_len {
      let sigma_x = left / 8 + dx
      let sigma_group_x = sigma_x >> sigma_group_dim_shift
      let sigma_inner_x = sigma_x & sigma_group_dim_mask
      let sigma_grid_idx = sigma_group_y * groups_per_row + sigma_group_x
      if sigma_grid_map[sigma_grid_idx] is Some(grid) {
        sigma_row[dx] = grid.buf[sigma_inner_y * grid.width + sigma_inner_x]
      }
    }
    for dy in 0..<job_height {
      let y = base_y + dy
      for c in 0..<3 {
        let g = input[c]
        for idx in 0..<7 {
          let yy = epf_mirror(y + idx - 3, height)
          input_rows[c * 7 + idx] = g.offset + yy * g.stride
        }
      }
      let image_y = top + y
      epf_row(
        step, input, input_rows, output, y, width, image_y, sigma_row, epf_params,
      )
    }
    base_y += 8
  }
}

///|
/// `util::mirror`: reflects `offset` into `0..len`.
fn epf_mirror(offset : Int32, len : Int32) -> Int32 {
  let mut offset = offset
  while true {
    if offset < 0 {
      offset = -(offset + 1)
    } else if offset >= len {
      offset = -(offset + 1) + len * 2
    } else {
      return offset
    }
  }
  0
}

///|
let epf_kernel_1 : FixedArray[Int32] = [0, -1, 0, 1, -1, 0, 1, 0]

///|
let epf_kernel_2 : FixedArray[Int32] = [
  0, -2, -1, -1, 0, -1, 1, -1, -2, 0, -1, 0, 1, 0, 2, 0, -1, 1, 0, 1, 1, 1, 0, 2,
]

///|
/// `epf_kernel_offsets::<STEP>()` as flattened `(x, y)` pairs.
fn epf_kernel_offsets(step : Int32) -> FixedArray[Int32] {
  if step == 0 {
    epf_kernel_2
  } else if step == 1 || step == 2 {
    epf_kernel_1
  } else {
    abort("epf: invalid step")
  }
}

///|
let epf_dist_0 : FixedArray[Int32] = [0, -1, 1, 0, 0, 0, -1, 0, 0, 1]

///|
let epf_dist_1 : FixedArray[Int32] = [0, -1, 0, 0, 0, 1, -1, 0, 1, 0]

///|
let epf_dist_2 : FixedArray[Int32] = [0, 0]

///|
/// `epf_dist_offsets::<STEP>()` as flattened `(x, y)` pairs.
fn epf_dist_offsets(step : Int32) -> FixedArray[Int32] {
  if step == 0 {
    epf_dist_0
  } else if step == 1 {
    epf_dist_1
  } else if step == 2 {
    epf_dist_2
  } else {
    abort("epf: invalid step")
  }
}

///|
/// `epf_row::<STEP>` (generic). `input_rows[c * 7 + k]` is the buffer offset of
/// row `y + k - 3` (mirrored) of channel `c`; `out_y` is the output row.
///
/// Upstream splits the row into a mirrored left edge, an unmirrored inner part
/// and a mirrored right edge; `mirror` is the identity for in-range indices, so
/// one loop that mirrors only out-of-range indices gives the same result.
fn epf_row(
  step : Int32,
  input : Array[@grid.SubGrid[Float]],
  input_rows : FixedArray[Int32],
  output : Array[@grid.SubGrid[Float]],
  out_y : Int32,
  width : Int32,
  y : Int32,
  sigma_row : FixedArray[Float],
  epf_params : EpfKernelParams,
) -> Unit {
  let kernel_offsets = epf_kernel_offsets(step)
  let dist_offsets = epf_dist_offsets(step)
  let num_kernel = kernel_offsets.length() / 2
  let num_dist = dist_offsets.length() / 2
  let step_multiplier : Float = if step == 0 {
    epf_params.pass0_sigma_scale
  } else if step == 2 {
    epf_params.pass2_sigma_scale
  } else {
    1.0
  }
  let border_sad_mul = epf_params.border_sad_mul
  let channel_scale = epf_params.channel_scale
  let is_y_border = ((y + 1) & 6) == 0
  let sm = FixedArray::make(8, step_multiplier)
  if is_y_border {
    for i in 0..<8 {
      sm[i] = step_multiplier * border_sad_mul
    }
  } else {
    sm[0] = sm[0] * border_sad_mul
    sm[7] = sm[7] * border_sad_mul
  }
  let in0 = input[0].buf
  let in1 = input[1].buf
  let in2 = input[2].buf
  let ins = [in0, in1, in2]
  let out_off = FixedArray::make(3, 0)
  for c in 0..<3 {
    out_off[c] = output[c].offset + out_y * output[c].stride
  }
  let sum_channels = FixedArray::make(3, (0.0 : Float))
  for dx in 0..<width {
    let sm_idx = dx & 7
    let sigma_val = sigma_row[dx / 8]
    if sigma_val < 0.3 {
      for c in 0..<3 {
        output[c].buf[out_off[c] + dx] = ins[c][input_rows[c * 7 + 3] + dx]
      }
      continue
    }
    let mut sum_weights : Float = 1.0
    for c in 0..<3 {
      sum_channels[c] = ins[c][input_rows[c * 7 + 3] + dx]
    }
    for k in 0..<num_kernel {
      let kx = kernel_offsets[2 * k]
      let ky = kernel_offsets[2 * k + 1]
      let kernel_dy = 3 + ky
      let kernel_dx = dx + kx
      let mut dist : Float = 0.0
      for c in 0..<3 {
        let scale = channel_scale[c]
        let buf = ins[c]
        let mut acc : Float = 0.0
        for i in 0..<num_dist {
          let ix = dist_offsets[2 * i]
          let iy = dist_offsets[2 * i + 1]
          let kdy = kernel_dy + iy
          let kdx = epf_index(kernel_dx + ix, width)
          let bdy = 3 + iy
          let bdx = epf_index(dx + ix, width)
          acc = acc +
            (buf[input_rows[c * 7 + kdy] + kdx] -
            buf[input_rows[c * 7 + bdy] + bdx]).abs()
        }
        dist = dist + scale * acc
      }
      let weight = epf_weight(dist, sigma_val, sm[sm_idx])
      sum_weights = sum_weights + weight
      let kdx = epf_index(kernel_dx, width)
      for c in 0..<3 {
        sum_channels[c] = sum_channels[c] +
          weight * ins[c][input_rows[c * 7 + kernel_dy] + kdx]
      }
    }
    for c in 0..<3 {
      output[c].buf[out_off[c] + dx] = sum_channels[c] / sum_weights
    }
  }
}

///|
fn epf_index(x : Int32, width : Int32) -> Int32 {
  if x >= 0 && x < width {
    x
  } else {
    epf_mirror(x, width)
  }
}

///|
/// 6.6 * (FRAC_1_SQRT_2 - 1.0), evaluated in f32.
let epf_neg_inv_sigma_base : Float = {
  let frac_1_sqrt_2 : Float = 0.707106781186547524400844362104849039
  let k : Float = 6.6
  k * (frac_1_sqrt_2 - 1.0)
}

///|
fn epf_weight(
  scaled_distance : Float,
  sigma : Float,
  step_multiplier : Float,
) -> Float {
  let neg_inv_sigma = epf_neg_inv_sigma_base / sigma * step_multiplier
  let v : Float = 1.0 + scaled_distance * neg_inv_sigma
  // f32::max(v, 0.0): NaN yields 0.0
  if v > 0.0 {
    v
  } else {
    0.0
  }
}
