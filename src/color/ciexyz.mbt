// Port of jxl-color/src/ciexyz.rs.

///|
let mat_bradford : FixedArray[Float] = [
  0.8951, 0.2664, -0.1614, -0.7502, 1.7135, 0.0367, 0.0389, -0.0685, 1.0296,
]

///|
let mat_bradford_inv : FixedArray[Float] = [
  0.9869929, -0.1470543, 0.1599627, 0.4323053, 0.5183603, 0.0492912, -0.0085287,
  0.0400428, 0.9684867,
]

///|
/// Types that represent an illuminant (white point) as xy-chromaticity.
pub(open) trait AsIlluminant {
  fn as_illuminant(Self) -> FixedArray[Float]
}

///|
/// Types that represent RGB primaries as xy-chromaticity (`[[x, y]; 3]`).
pub(open) trait AsPrimaries {
  fn as_primaries(Self) -> FixedArray[FixedArray[Float]]
}

///|
pub impl AsIlluminant for FixedArray[Float] with fn as_illuminant(self) {
  self
}

///|
pub impl AsIlluminant for WhitePoint with fn as_illuminant(self) {
  match self {
    D65 => illuminant_d65
    Custom(xy) => xy.as_float()
    E => illuminant_e
    Dci => illuminant_dci
  }
}

///|
pub impl AsPrimaries for FixedArray[FixedArray[Float]] with fn as_primaries(
  self,
) {
  self
}

///|
pub impl AsPrimaries for Primaries with fn as_primaries(self) {
  match self {
    Srgb => primaries_srgb
    Custom(red~, green~, blue~) =>
      [red.as_float(), green.as_float(), blue.as_float()]
    Bt2100 => primaries_bt2100
    P3 => primaries_p3
  }
}

///|
pub fn matmul3(
  a : FixedArray[Float],
  b : FixedArray[Float],
) -> FixedArray[Float] {
  let bcol0 : FixedArray[Float] = [b[0], b[3], b[6]]
  let bcol1 : FixedArray[Float] = [b[1], b[4], b[7]]
  let bcol2 : FixedArray[Float] = [b[2], b[5], b[8]]
  [
    a[0] * bcol0[0] + a[1] * bcol0[1] + a[2] * bcol0[2],
    a[0] * bcol1[0] + a[1] * bcol1[1] + a[2] * bcol1[2],
    a[0] * bcol2[0] + a[1] * bcol2[1] + a[2] * bcol2[2],
    a[3] * bcol0[0] + a[4] * bcol0[1] + a[5] * bcol0[2],
    a[3] * bcol1[0] + a[4] * bcol1[1] + a[5] * bcol1[2],
    a[3] * bcol2[0] + a[4] * bcol2[1] + a[5] * bcol2[2],
    a[6] * bcol0[0] + a[7] * bcol0[1] + a[8] * bcol0[2],
    a[6] * bcol1[0] + a[7] * bcol1[1] + a[8] * bcol1[2],
    a[6] * bcol2[0] + a[7] * bcol2[1] + a[8] * bcol2[2],
  ]
}

///|
pub fn matmul3vec(
  a : FixedArray[Float],
  b : FixedArray[Float],
) -> FixedArray[Float] {
  [
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
    a[3] * b[0] + a[4] * b[1] + a[5] * b[2],
    a[6] * b[0] + a[7] * b[1] + a[8] * b[2],
  ]
}

///|
pub fn matinv(mat : FixedArray[Float]) -> FixedArray[Float] {
  let det = mat[0] * (mat[4] * mat[8] - mat[5] * mat[7]) +
    mat[1] * (mat[5] * mat[6] - mat[3] * mat[8]) +
    mat[2] * (mat[3] * mat[7] - mat[4] * mat[6])
  [
    (mat[4] * mat[8] - mat[5] * mat[7]) / det,
    (mat[7] * mat[2] - mat[8] * mat[1]) / det,
    (mat[1] * mat[5] - mat[2] * mat[4]) / det,
    (mat[5] * mat[6] - mat[3] * mat[8]) / det,
    (mat[8] * mat[0] - mat[6] * mat[2]) / det,
    (mat[2] * mat[3] - mat[0] * mat[5]) / det,
    (mat[3] * mat[7] - mat[4] * mat[6]) / det,
    (mat[6] * mat[1] - mat[7] * mat[0]) / det,
    (mat[0] * mat[4] - mat[1] * mat[3]) / det,
  ]
}

///|
pub fn[I : AsIlluminant] illuminant_to_xyz(illuminant : I) -> FixedArray[Float] {
  let xy = illuminant.as_illuminant()
  let x = xy[0]
  let y = xy[1]
  [x / y, 1.0, ((1.0 : Float) - x) / y - 1.0]
}

///|
pub fn[F : AsIlluminant, T : AsIlluminant] adapt_mat(
  from_illuminant : F,
  to_illuminant : T,
) -> FixedArray[Float] {
  let from_w = illuminant_to_xyz(from_illuminant)
  let to_w = illuminant_to_xyz(to_illuminant)
  if from_w[0] == to_w[0] && from_w[1] == to_w[1] && from_w[2] == to_w[2] {
    return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  }
  let from_lms = matmul3vec(mat_bradford, from_w)
  let to_lms = matmul3vec(mat_bradford, to_w)
  let mul : FixedArray[Float] = [
    to_lms[0] / from_lms[0],
    to_lms[1] / from_lms[1],
    to_lms[2] / from_lms[2],
  ]
  let multiplied = FixedArray::makei(9, idx => mat_bradford[idx] * mul[idx / 3])
  matmul3(mat_bradford_inv, multiplied)
}

///|
fn primaries_matrix(p : FixedArray[FixedArray[Float]]) -> FixedArray[Float] {
  [
    p[0][0],
    p[1][0],
    p[2][0],
    p[0][1],
    p[1][1],
    p[2][1],
    (1.0 : Float) - p[0][0] - p[0][1],
    (1.0 : Float) - p[1][0] - p[1][1],
    (1.0 : Float) - p[2][0] - p[2][1],
  ]
}

///|
pub fn[P : AsPrimaries, W : AsIlluminant] primaries_to_xyz_mat(
  primaries : P,
  wp : W,
) -> FixedArray[Float] {
  let primaries = primaries_matrix(primaries.as_primaries())
  let primaries_inv = matinv(primaries)
  let w_xyz = illuminant_to_xyz(wp)
  let mul = matmul3vec(primaries_inv, w_xyz)
  for idx in 0..<9 {
    primaries[idx] = primaries[idx] * mul[idx % 3]
  }
  primaries
}

///|
pub fn[P : AsPrimaries, W : AsIlluminant] xyz_to_primaries_mat(
  primaries : P,
  wp : W,
) -> FixedArray[Float] {
  let primaries = primaries_matrix(primaries.as_primaries())
  let primaries_inv = matinv(primaries)
  let w_xyz = illuminant_to_xyz(wp)
  let mul = matmul3vec(primaries_inv, w_xyz)
  for idx in 0..<9 {
    primaries_inv[idx] = primaries_inv[idx] / mul[idx / 3]
  }
  primaries_inv
}
