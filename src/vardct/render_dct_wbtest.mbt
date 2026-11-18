///|
fn reference_forward(input : FixedArray[Float]) -> FixedArray[Double] {
  let s = input.length()
  FixedArray::makei(s, k => {
    let mut exp_value = 0.0
    for n in 0..<s {
      let cos = @math.cos(
        (k * (2 * n + 1)).to_double() / s.to_double() * @math.PI / 2.0,
      )
      exp_value += input[n].to_double() * cos
    }
    exp_value /= s.to_double()
    if k != 0 {
      exp_value *= (2.0 : Double).sqrt()
    }
    exp_value
  })
}

///|
fn reference_inverse(input : FixedArray[Float]) -> FixedArray[Double] {
  let s = input.length()
  FixedArray::makei(s, k => {
    let mut exp_value = input[0].to_double()
    for n in 1..<s {
      let cos = @math.cos(
        (n * (2 * k + 1)).to_double() / s.to_double() * @math.PI / 2.0,
      )
      exp_value += input[n].to_double() * cos * (2.0 : Double).sqrt()
    }
    exp_value
  })
}

///|
/// The upstream tests: quantize to 1/65536 and compare exactly.
fn check_quantized(
  original : FixedArray[Float],
  direction : DctDirection,
) -> Unit raise {
  let n = original.length()
  let io = original.copy()
  let scratch = FixedArray::make(n, (0.0 : Float))
  dct(io, 0, n, scratch, 0, direction)
  let expected = if direction == Forward {
    reference_forward(original)
  } else {
    reference_inverse(original)
  }
  for k in 0..<n {
    let q_expected = (expected[k] * 65536.0).to_int()
    let q_actual = (io[k] * 65536.0).to_int()
    assert_eq(q_expected, q_actual)
  }
}

///|
test "forward_dct_2" {
  check_quantized([-1.0, 3.0], Forward)
}

///|
test "forward_dct_4" {
  check_quantized([-1.0, 2.0, 3.0, -4.0], Forward)
}

///|
test "forward_dct_8" {
  check_quantized([1.0, 0.3, 1.0, 2.0, -2.0, -0.1, 1.0, 0.1], Forward)
}

///|
test "backward_dct_2" {
  check_quantized([3.0, 0.2], Inverse)
}

///|
test "backward_dct_4" {
  check_quantized([3.0, 0.2, 0.3, -1.0], Inverse)
}

///|
test "backward_dct_8" {
  check_quantized([3.0, 0.0, 0.0, -1.0, 0.0, 0.3, 0.2, 0.0], Inverse)
}

///|
test "1D DCT of all sizes matches O(n^2) float64 reference" {
  let mut n = 2
  while n <= 256 {
    let rng = { state: n.reinterpret_as_uint(), }
    let input = FixedArray::makei(n, _ => rng.next())
    for dir_idx in 0..<2 {
      let direction = if dir_idx == 0 { Forward } else { Inverse }
      let io = input.copy()
      let scratch = FixedArray::make(n, (0.0 : Float))
      dct(io, 0, n, scratch, 0, direction)
      let expected = if dir_idx == 0 {
        reference_forward(input)
      } else {
        reference_inverse(input)
      }
      // Inverse outputs grow with sqrt(n); scale the tolerance accordingly.
      let tol = if dir_idx == 0 { 1.0e-5 } else { 2.0e-5 * n.to_double() }
      for k in 0..<n {
        let diff = (io[k].to_double() - expected[k]).abs()
        assert_true(diff < tol, msg="n=\{n} dir=\{dir_idx} k=\{k} diff=\{diff}")
      }
    }
    n *= 2
  }
}

///|
test "IDCT(DCT(x)) == x for all 2D sizes" {
  let sizes = [1, 2, 4, 8, 16, 32, 64, 128, 256]
  for w in sizes {
    for h in sizes {
      if w * h > 65536 {
        continue
      }
      let rng = { state: (w * 7 + h).reinterpret_as_uint(), }
      let input = FixedArray::makei(w * h, _ => rng.next())
      let buf = input.copy()
      let grid = @grid.SubGrid::from_buf(buf, 0, w, h, w)
      dct_2d(grid, Forward)
      dct_2d(grid, Inverse)
      for i in 0..<(w * h) {
        let diff = (buf[i] - input[i]).abs()
        assert_true(diff < 1.0e-4, msg="\{w}x\{h} i=\{i} diff=\{diff}")
      }
    }
  }
}

///|
test "dct_2d on a strided subgrid only touches the view" {
  let buf = FixedArray::make(20 * 10, (7.0 : Float))
  let grid = @grid.SubGrid::from_buf(buf, 2 * 20 + 3, 8, 4, 20)
  for y in 0..<4 {
    for x in 0..<8 {
      grid.set(x, y, Float::from_int(x * y))
    }
  }
  dct_2d(grid, Forward)
  dct_2d(grid, Inverse)
  for y in 0..<10 {
    for x in 0..<20 {
      let inside = x >= 3 && x < 11 && y >= 2 && y < 6
      let v = buf[y * 20 + x]
      if inside {
        assert_true((v - Float::from_int((x - 3) * (y - 2))).abs() < 1.0e-4)
      } else {
        assert_eq(v, 7.0)
      }
    }
  }
}
