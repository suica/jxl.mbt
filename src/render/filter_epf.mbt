// Port of jxl-render filter/epf.rs, filter/impls/{generic,x86_64}.rs,
// filter/impls/generic/epf.rs and filter/impls/x86_64/epf_sse41.rs
// (edge-preserving filter).
//
// Upstream runs a SIMD row handler for the inner part of rows that have three
// rows above and four below inside the region (`merged_input_rows`), and the
// generic handler for the rest. The SSE4.1 (x86_64), NEON (aarch64) and
// simd128 (wasm32 release build) handlers compute the same operations in the
// same order: for passes 0 and 2 that order equals the generic one, for pass 1
// the distance sums are added in a different order (see
// `epf_simd_step1_pixel`), which changes results in the last bits. This port
// does what upstream does on those targets: the SIMD order on the SIMD part
// of a row, the generic order elsewhere.

///|
/// `filter::apply_epf`.
fn apply_epf(
  fb_image : ImageWithRegion,
  fb_scratch_arr : FixedArray[@grid.Grid[Float]],
  color_padded_region : Region,
  lf_groups : Map[Int32, @frame.LfGroup],
  frame_header : @frame.FrameHeader,
  epf_params : @frame.EpfParams,
  pool~ : @threadpool.JxlThreadPool = @threadpool.JxlThreadPool::none(),
) -> Unit {
  let region = fb_image.regions_and_shifts()[0].0
  guard region.contains(color_padded_region) else {
    abort("assertion failed: region.contains(color_padded_region)")
  }
  let left = abs_diff(region.left, color_padded_region.left)
  let top = abs_diff(region.top, color_padded_region.top)
  let fb = fb_image
    .as_color_floats_mut()
    .map(g => {
      g
      .as_subgrid()
      .subgrid(left, top, color_padded_region.width, color_padded_region.height)
    })
  let num_lf_groups = frame_header.num_lf_groups()
  let sigma_grid_map : FixedArray[@grid.Grid[Float]?] = FixedArray::make(
    num_lf_groups,
    None,
  )
  for lf_group_idx, lf_group in lf_groups {
    if lf_group.hf_meta is Some(hf_meta) {
      sigma_grid_map[lf_group_idx] = Some(hf_meta.epf_sigma)
    }
  }
  let result_in_scratch = apply_epf_views(
    fb,
    fb_scratch_arr,
    color_padded_region,
    frame_header.group_dim(),
    frame_header.lf_groups_per_row(),
    sigma_grid_map,
    epf_params,
    pool,
  )
  if result_in_scratch {
    let left = color_padded_region.left
    let top = color_padded_region.top
    for idx, grid in fb_scratch_arr {
      let region : Region = {
        width: grid.width(),
        height: grid.height(),
        left,
        top,
      }
      fb_image.replace_channel(idx, F32(grid), region)
    }
  }
}

///|
/// The three passes of `apply_epf` on the colour views `fb` (cut to
/// `color_padded_region`) with `fb_scratch_arr` as the second buffer. Returns
/// whether the result is in `fb_scratch_arr` (`iters` is 1 or 3).
fn apply_epf_views(
  fb : FixedArray[@grid.SubGrid[Float]],
  fb_scratch_arr : FixedArray[@grid.Grid[Float]],
  color_padded_region : Region,
  group_dim : Int32,
  lf_groups_per_row : Int32,
  sigma_grid_map : FixedArray[@grid.Grid[Float]?],
  epf_params : @frame.EpfParams,
  pool : @threadpool.JxlThreadPool,
) -> Bool {
  let iters = epf_params.iters
  let mut fb = fb
  let mut fb_scratch = fb_scratch_arr.map(g => g.as_subgrid())
  let run = (step : Int32, input, output) => {
    run_epf_rows(
      step, input, output, color_padded_region, group_dim, lf_groups_per_row, sigma_grid_map,
      epf_params, pool,
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
/// One EPF pass (`impls::epf::<STEP>` → `run_epf_rows`), reading `input` and
/// writing `output`. Rows are split into jobs of 8 rows; the sigma row is the
/// per-worker state of `for_each_vec_with` (with no thread pool, one state is
/// shared by all jobs in order, so entries of LF groups without sigma keep the
/// value of the previous job).
fn run_epf_rows(
  step : Int32,
  input : FixedArray[@grid.SubGrid[Float]],
  output : FixedArray[@grid.SubGrid[Float]],
  color_padded_region : Region,
  group_dim : Int32,
  lf_groups_per_row : Int32,
  sigma_grid_map : FixedArray[@grid.Grid[Float]?],
  epf_params : @frame.EpfParams,
  pool : @threadpool.JxlThreadPool,
) -> Unit {
  let { left, top, width, height, } = color_padded_region
  guard left >= 0 && top >= 0 else {
    abort("assertion failed: left >= 0 && top >= 0")
  }
  guard left % 8 == 0 else { abort("assertion failed: left % 8 == 0") }
  guard top % 8 == 0 else { abort("assertion failed: top % 8 == 0") }
  let jobs = []
  let mut dy = 0
  while dy < height {
    jobs.push(dy)
    dy += 8
  }
  let sigma_group_dim_shift = group_dim.ctz()
  let sigma_group_dim_mask = group_dim - 1
  let groups_per_row = lf_groups_per_row
  let sigma_len = (width + 7) / 8
  pool.for_each_vec_with(
    jobs,
    FixedArray::make(sigma_len, epf_params.sigma_for_modular),
    (state, base_y) => {
      let sigma_row = state.val
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
          let width = grid.width()
          sigma_row[dx] = grid.buf()[sigma_inner_y * width + sigma_inner_x]
        }
      }
      let input_rows = FixedArray::make(21, 0)
      for dy in 0..<job_height {
        let y = base_y + dy
        for c in 0..<3 {
          let g = input[c]
          for idx in 0..<7 {
            let yy = mirror(y + idx - 3, height)
            input_rows[c * 7 + idx] = g.offset + yy * g.stride
          }
        }
        // `merged_input_rows` exists (and the SIMD handler runs) when the
        // seven rows need no mirroring.
        let merged = y >= 3 && y + 4 <= height
        let image_y = top + y
        epf_row(
          step, input, input_rows, output, y, width, image_y, sigma_row, epf_params,
          merged,
        )
      }
    },
  )
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
  input : FixedArray[@grid.SubGrid[Float]],
  input_rows : FixedArray[Int32],
  output : FixedArray[@grid.SubGrid[Float]],
  out_y : Int32,
  width : Int32,
  y : Int32,
  sigma_row : FixedArray[Float],
  epf_params : @frame.EpfParams,
  merged : Bool,
) -> Unit {
  let kernel_offsets = epf_kernel_offsets(step)
  let dist_offsets = epf_dist_offsets(step)
  let num_kernel = kernel_offsets.length() / 2
  let num_dist = dist_offsets.length() / 2
  let step_multiplier : Float = if step == 0 {
    epf_params.sigma.pass0_sigma_scale
  } else if step == 2 {
    epf_params.sigma.pass2_sigma_scale
  } else {
    1.0
  }
  let border_sad_mul = epf_params.sigma.border_sad_mul
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
  // The SIMD handler (pass 1 only differs) covers 4..((width - padding) & !3)
  // when the row has `merged_input_rows` and width >= 2 * padding.
  let padding = 3 - step
  let (simd_start, simd_end) = if step == 1 && merged && width >= padding * 2 {
    let end = (width - padding) & -4
    if 4 > end {
      (4, 4)
    } else {
      (4, end)
    }
  } else {
    (0, 0)
  }
  for dx in 0..<width {
    let sm_idx = dx & 7
    let sigma_val = sigma_row[dx / 8]
    if dx >= simd_start && dx < simd_end && sigma_val >= 0.3 {
      epf_simd_step1_pixel(
        ins,
        input_rows,
        output,
        out_off,
        dx,
        sigma_val,
        sm[sm_idx],
        channel_scale,
      )
      continue
    }
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
    mirror(x, width)
  }
}

///|
/// One pixel of pass 1 as the SIMD handlers compute it
/// (`epf_row_x86_64_sse41::<1>`; NEON and simd128 use the same order). No
/// index is mirrored: the caller only uses it inside the SIMD range.
fn epf_simd_step1_pixel(
  ins : Array[FixedArray[Float]],
  input_rows : FixedArray[Int32],
  output : FixedArray[@grid.SubGrid[Float]],
  out_off : FixedArray[Int32],
  x : Int32,
  sigma_val : Float,
  sm : Float,
  channel_scale : FixedArray[Float],
) -> Unit {
  let mut sum_weights : Float = 1.0
  let sum0 = ins[0][input_rows[3] + x]
  let sum1 = ins[1][input_rows[7 + 3] + x]
  let sum2 = ins[2][input_rows[14 + 3] + x]
  let sums : FixedArray[Float] = [sum0, sum1, sum2]
  // (0, -1), (0, 1)
  {
    let mut dist0 : Float = 0.0
    let mut dist1 : Float = 0.0
    for c in 0..<3 {
      let scale = channel_scale[c]
      let b = ins[c]
      let r1 = input_rows[c * 7 + 1]
      let r2 = input_rows[c * 7 + 2]
      let r3 = input_rows[c * 7 + 3]
      let r4 = input_rows[c * 7 + 4]
      let r5 = input_rows[c * 7 + 5]
      let v0 = b[r1 + x]
      let v1 = b[r2 + x]
      let v2 = b[r3 + x]
      let v3 = b[r4 + x]
      let v4 = b[r5 + x]
      let tmp = (v1 - v2).abs() + (v3 - v2).abs()
      let mut acc0 = tmp + (v1 - v0).abs()
      let mut acc1 = tmp + (v3 - v4).abs()
      let v1_left = b[r2 + x - 1]
      let v2_left = b[r3 + x - 1]
      let v3_left = b[r4 + x - 1]
      let v1_right = b[r2 + x + 1]
      let v2_right = b[r3 + x + 1]
      let v3_right = b[r4 + x + 1]
      acc0 = acc0 + (v1_left - v2_left).abs()
      acc1 = acc1 + (v3_left - v2_left).abs()
      acc0 = acc0 + (v1_right - v2_right).abs()
      acc1 = acc1 + (v3_right - v2_right).abs()
      dist0 = scale * acc0 + dist0
      dist1 = scale * acc1 + dist1
    }
    let weight0 = epf_weight(dist0, sigma_val, sm)
    let weight1 = epf_weight(dist1, sigma_val, sm)
    sum_weights = sum_weights + weight0 + weight1
    for c in 0..<3 {
      let weighted0 = weight0 * ins[c][input_rows[c * 7 + 2] + x]
      let weighted1 = weight1 * ins[c][input_rows[c * 7 + 4] + x]
      sums[c] = sums[c] + weighted0 + weighted1
    }
  }
  // (-1, 0), (1, 0)
  {
    let mut dist0 : Float = 0.0
    let mut dist1 : Float = 0.0
    for c in 0..<3 {
      let scale = channel_scale[c]
      let b = ins[c]
      let r2 = input_rows[c * 7 + 2]
      let r3 = input_rows[c * 7 + 3]
      let r4 = input_rows[c * 7 + 4]
      let v0r = b[r2 + x + 1]
      let v0 = b[r2 + x]
      let v0l = b[r2 + x - 1]
      let mut acc0 = (v0l - v0).abs()
      let mut acc1 = (v0r - v0).abs()
      let v1rr = b[r3 + x + 2]
      let v1r = b[r3 + x + 1]
      let v1 = b[r3 + x]
      let v1l = b[r3 + x - 1]
      let v1ll = b[r3 + x - 2]
      acc0 = acc0 + (v1ll - v1l).abs()
      acc0 = acc0 + (v1 - v1l).abs()
      acc0 = acc0 + (v1 - v1r).abs()
      acc1 = acc1 + (v1 - v1l).abs()
      acc1 = acc1 + (v1 - v1r).abs()
      acc1 = acc1 + (v1rr - v1r).abs()
      let v2r = b[r4 + x + 1]
      let v2 = b[r4 + x]
      let v2l = b[r4 + x - 1]
      acc0 = acc0 + (v2l - v2).abs()
      acc1 = acc1 + (v2r - v2).abs()
      dist0 = scale * acc0 + dist0
      dist1 = scale * acc1 + dist1
    }
    let weight0 = epf_weight(dist0, sigma_val, sm)
    let weight1 = epf_weight(dist1, sigma_val, sm)
    sum_weights = sum_weights + weight0 + weight1
    for c in 0..<3 {
      let weighted0 = weight0 * ins[c][input_rows[c * 7 + 3] + x - 1]
      let weighted1 = weight1 * ins[c][input_rows[c * 7 + 3] + x + 1]
      sums[c] = sums[c] + weighted0 + weighted1
    }
  }
  for c in 0..<3 {
    output[c].buf[out_off[c] + x] = sums[c] / sum_weights
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
