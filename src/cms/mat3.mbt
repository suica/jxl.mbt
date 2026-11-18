// 3x3 matrix helpers (`cmsmtrx.c`) and Lab/XYZ conversions (`cmspcs.c`).
// Matrices are row-major `FixedArray[Double]` of 9 elements.

///|
fn mat3_identity() -> FixedArray[Double] {
  [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
}

///|
/// `CloseEnough`
fn close_enough(a : Double, b : Double) -> Bool {
  (b - a).abs() < 1.0 / 65535.0
}

///|
/// `_cmsMAT3isIdentity`
fn mat3_is_identity(a : FixedArray[Double]) -> Bool {
  let id = mat3_identity()
  for i in 0..<9 {
    if !close_enough(a[i], id[i]) {
      return false
    }
  }
  true
}

///|
/// `_cmsMAT3per`: r = a * b
fn mat3_per(
  a : FixedArray[Double],
  b : FixedArray[Double],
) -> FixedArray[Double] {
  let r = FixedArray::make(9, 0.0)
  for i in 0..<3 {
    for j in 0..<3 {
      r[i * 3 + j] = a[i * 3 + 0] * b[0 * 3 + j] +
        a[i * 3 + 1] * b[1 * 3 + j] +
        a[i * 3 + 2] * b[2 * 3 + j]
    }
  }
  r
}

///|
/// `_cmsMAT3inverse`
fn mat3_inverse(a : FixedArray[Double]) -> FixedArray[Double]? {
  let c0 = a[4] * a[8] - a[5] * a[7]
  let c1 = -a[3] * a[8] + a[5] * a[6]
  let c2 = a[3] * a[7] - a[4] * a[6]
  let det = a[0] * c0 + a[1] * c1 + a[2] * c2
  if det.abs() < MATRIX_DET_TOLERANCE {
    return None
  }
  let b = FixedArray::make(9, 0.0)
  b[0] = c0 / det
  b[1] = (a[2] * a[7] - a[1] * a[8]) / det
  b[2] = (a[1] * a[5] - a[2] * a[4]) / det
  b[3] = c1 / det
  b[4] = (a[0] * a[8] - a[2] * a[6]) / det
  b[5] = (a[2] * a[3] - a[0] * a[5]) / det
  b[6] = c2 / det
  b[7] = (a[1] * a[6] - a[0] * a[7]) / det
  b[8] = (a[0] * a[4] - a[1] * a[3]) / det
  Some(b)
}

///|
/// `_cmsMAT3eval`
fn mat3_eval(
  a : FixedArray[Double],
  v0 : Double,
  v1 : Double,
  v2 : Double,
) -> (Double, Double, Double) {
  (
    a[0] * v0 + a[1] * v1 + a[2] * v2,
    a[3] * v0 + a[4] * v1 + a[5] * v2,
    a[6] * v0 + a[7] * v1 + a[8] * v2,
  )
}

///|
/// `_cmsMAT3solve`
fn mat3_solve(
  a : FixedArray[Double],
  b : (Double, Double, Double),
) -> (Double, Double, Double)? {
  guard mat3_inverse(a) is Some(a_1) else { return None }
  Some(mat3_eval(a_1, b.0, b.1, b.2))
}

///|
/// `f` of `cmsXYZ2Lab`
fn lab_f(t : Double) -> Double {
  let limit = 24.0 / 116.0 * (24.0 / 116.0) * (24.0 / 116.0)
  if t <= limit {
    841.0 / 108.0 * t + 16.0 / 116.0
  } else {
    pow(t, 1.0 / 3.0)
  }
}

///|
/// `f_1` of `cmsLab2XYZ`
fn lab_f_1(t : Double) -> Double {
  let limit = 24.0 / 116.0
  if t <= limit {
    return 108.0 / 841.0 * (t - 16.0 / 116.0)
  }
  t * t * t
}

///|
/// `cmsXYZ2Lab` with a D50 white point.
fn xyz_to_lab(x : Double, y : Double, z : Double) -> (Double, Double, Double) {
  let fx = lab_f(x / D50_X)
  let fy = lab_f(y / D50_Y)
  let fz = lab_f(z / D50_Z)
  (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
}

///|
/// `cmsLab2XYZ` with a D50 white point.
fn lab_to_xyz(l : Double, a : Double, b : Double) -> (Double, Double, Double) {
  let y = (l + 16.0) / 116.0
  let x = y + 0.002 * a
  let z = y - 0.005 * b
  (lab_f_1(x) * D50_X, lab_f_1(y) * D50_Y, lab_f_1(z) * D50_Z)
}
