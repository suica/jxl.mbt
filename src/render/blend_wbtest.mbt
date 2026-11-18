///|
fn grid_of(w : Int, h : Int, vals : Array[Float]) -> @grid.Grid[Float] {
  let g = @grid.Grid::new(w, h, (0.0 : Float))
  for i, v in vals {
    g.buf()[i] = v
  }
  g
}

///|
fn params(mode : BlendMode, w : Int, h : Int) -> BlendParams {
  { mode, base_topleft: (0, 0), new_topleft: (0, 0), width: w, height: h }
}

///|
test "blend_single replace/add/mul with offsets" {
  let base = grid_of(3, 2, [1, 2, 3, 4, 5, 6])
  let new = grid_of(2, 2, [10, 20, 30, 40])
  let p = params(Replace, 1, 2)
  p.base_topleft = (2, 0)
  p.new_topleft = (1, 0)
  blend_single(base.as_subgrid(), new.as_subgrid(), p)
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [1, 2, 20, 4, 5, 40]>
  ))
  blend_single(base.as_subgrid(), new.as_subgrid(), params(Add, 2, 2))
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [11, 22, 20, 34, 45, 40]>
  ))
  let m = grid_of(2, 1, [2, -1])
  blend_single(base.as_subgrid(), m.as_subgrid(), params(Mul(true), 2, 1))
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [11, 0, 20, 34, 45, 40]>
  ))
}

///|
test "blend_single blend modes" {
  // Non-premultiplied blend: new over base.
  let base = grid_of(1, 1, [0.25])
  let new = grid_of(1, 1, [0.75])
  let base_a = grid_of(1, 1, [1.0])
  let new_a = grid_of(1, 1, [0.5])
  let mode = Blend({
    base: Some(base_a.as_subgrid()),
    new: Some(new_a.as_subgrid()),
    clamp: false,
    swapped: false,
    premultiplied: false,
  })
  blend_single(base.as_subgrid(), new.as_subgrid(), params(mode, 1, 1))
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [0.5]>
  ))
  // Premultiplied.
  let base = grid_of(1, 1, [0.25])
  let mode = Blend({
    base: Some(base_a.as_subgrid()),
    new: Some(new_a.as_subgrid()),
    clamp: false,
    swapped: false,
    premultiplied: true,
  })
  blend_single(base.as_subgrid(), new.as_subgrid(), params(mode, 1, 1))
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [0.875]>
  ))
  // MixAlpha.
  let a = grid_of(1, 1, [0.5])
  let b = grid_of(1, 1, [0.5])
  blend_single(
    a.as_subgrid(),
    b.as_subgrid(),
    params(MixAlpha(clamp=false, swapped=false), 1, 1),
  )
  debug_inspect(a.buf(), content=(
    #|<FixedArray: [0.75]>
  ))
  // MulAdd.
  let base = grid_of(1, 1, [0.25])
  let mode = MulAdd({
    base: None,
    new: Some(new_a.as_subgrid()),
    clamp: false,
    swapped: false,
    premultiplied: false,
  })
  blend_single(base.as_subgrid(), new.as_subgrid(), params(mode, 1, 1))
  debug_inspect(base.buf(), content=(
    #|<FixedArray: [0.625]>
  ))
}

///|
test "upsample_nn and mirror" {
  let g = @grid.Grid::new(2, 1, 0)
  g.buf()[0] = 1
  g.buf()[1] = 2
  guard ImageBuffer::I32(g).upsample_nn(1, None) is I32(out) else {
    fail("type")
  }
  debug_inspect((out.width(), out.height()), content="(4, 2)")
  debug_inspect(out.buf(), content=(
    #|<FixedArray: [1, 1, 2, 2, 1, 1, 2, 2]>
  ))
  debug_inspect(
    [mirror(-1, 4), mirror(-2, 4), mirror(4, 4), mirror(5, 4), mirror(2, 4)],
    content="[0, 1, 3, 2, 2]",
  )
}

///|
test "padded grid mirror" {
  let p = PaddedGrid::with_alloc_tracker(2, 2, 1, 0, None)
  let b = p.buf_padded_mut()
  // interior at (1..3, 1..3) of a 4x4 buffer
  b[5] = 1
  b[6] = 2
  b[9] = 3
  b[10] = 4
  p.mirror_edges_padding()
  debug_inspect(
    p.buf_padded(),
    content=(
      #|<FixedArray: [1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 4, 4]>
    ),
  )
}
