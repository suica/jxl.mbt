// Port of moxcms 0.9.0 `matrix.rs` (the operations reachable from
// `ColorProfile::create_transform_f32`).
//
// `mlaf(acc, a, b)` is `acc + a * b` (unfused): upstream builds for x86_64
// without `target_feature = "fma"`, so its `mlaf` takes the non-FMA branch.

///|
pub(all) struct Matrix3f {
  v : FixedArray[FixedArray[Float]]
}

///|
pub(all) struct Matrix3d {
  v : FixedArray[FixedArray[Double]]
}

///|
pub(all) struct Vector3f {
  v : FixedArray[Float]
}

///|
pub(all) struct Vector3d {
  v : FixedArray[Double]
}

///|
#derive(Eq, Debug)
pub(all) struct Xyz {
  x : Float
  y : Float
  z : Float
}

///|
#derive(Eq, Debug)
pub(all) struct Xyzd {
  x : Double
  y : Double
  z : Double
}

///|
pub fn Xyzd::default() -> Xyzd {
  { x: 0.0, y: 0.0, z: 0.0, }
}

///|
pub fn Xyz::to_xyzd(self : Xyz) -> Xyzd {
  { x: self.x.to_double(), y: self.y.to_double(), z: self.z.to_double(), }
}

///|
pub fn Xyzd::to_vector_d(self : Xyzd) -> Vector3d {
  { v: [self.x, self.y, self.z], }
}

///|
pub fn Matrix3f::new(v : FixedArray[FixedArray[Float]]) -> Matrix3f {
  { v, }
}

///|
pub fn Matrix3f::zero() -> Matrix3f {
  { v: [[0, 0, 0], [0, 0, 0], [0, 0, 0]], }
}

///|
pub fn Matrix3f::identity() -> Matrix3f {
  { v: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], }
}

///|
pub fn Matrix3d::identity() -> Matrix3d {
  { v: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], }
}

///|
pub fn Matrix3d::zero() -> Matrix3d {
  { v: [[0, 0, 0], [0, 0, 0], [0, 0, 0]], }
}

///|
pub fn Matrix3f::transpose(self : Matrix3f) -> Matrix3f {
  let v = self.v
  {
    v: [
      [v[0][0], v[1][0], v[2][0]],
      [v[0][1], v[1][1], v[2][1]],
      [v[0][2], v[1][2], v[2][2]],
    ],
  }
}

///|
pub fn Matrix3d::transpose(self : Matrix3d) -> Matrix3d {
  let v = self.v
  {
    v: [
      [v[0][0], v[1][0], v[2][0]],
      [v[0][1], v[1][1], v[2][1]],
      [v[0][2], v[1][2], v[2][2]],
    ],
  }
}

///|
pub fn Matrix3d::eq(self : Matrix3d, other : Matrix3d) -> Bool {
  for i in 0..<3 {
    for j in 0..<3 {
      if self.v[i][j] != other.v[i][j] {
        return false
      }
    }
  }
  true
}

///|
pub fn Matrix3d::determinant(self : Matrix3d) -> Double? {
  let v = self.v
  let a0 = v[0][0] * v[1][1] * v[2][2]
  let a1 = v[0][1] * v[1][2] * v[2][0]
  let a2 = v[0][2] * v[1][0] * v[2][1]
  let s0 = v[0][2] * v[1][1] * v[2][0]
  let s1 = v[0][1] * v[1][0] * v[2][2]
  let s2 = v[0][0] * v[1][2] * v[2][1]
  let j = a0 + a1 + a2 - s0 - s1 - s2
  if j == 0.0 {
    return None
  }
  Some(j)
}

///|
pub fn Matrix3d::inverse(self : Matrix3d) -> Matrix3d {
  let v = self.v
  match self.determinant() {
    None => Matrix3d::identity()
    Some(determinant) => {
      let det = 1.0 / determinant
      let a = v[0][0]
      let b = v[0][1]
      let c = v[0][2]
      let d = v[1][0]
      let e = v[1][1]
      let f = v[1][2]
      let g = v[2][0]
      let h = v[2][1]
      let i = v[2][2]
      {
        v: [
          [(e * i - f * h) * det, (c * h - b * i) * det, (b * f - c * e) * det],
          [(f * g - d * i) * det, (a * i - c * g) * det, (c * d - a * f) * det],
          [(d * h - e * g) * det, (b * g - a * h) * det, (a * e - b * d) * det],
        ],
      }
    }
  }
}

///|
pub fn Matrix3f::determinant(self : Matrix3f) -> Float? {
  let v = self.v
  let a0 = v[0][0] * v[1][1] * v[2][2]
  let a1 = v[0][1] * v[1][2] * v[2][0]
  let a2 = v[0][2] * v[1][0] * v[2][1]
  let s0 = v[0][2] * v[1][1] * v[2][0]
  let s1 = v[0][1] * v[1][0] * v[2][2]
  let s2 = v[0][0] * v[1][2] * v[2][1]
  let j = a0 + a1 + a2 - s0 - s1 - s2
  if j == 0.0 {
    return None
  }
  Some(j)
}

///|
pub fn Matrix3f::inverse(self : Matrix3f) -> Matrix3f {
  let v = self.v
  match self.determinant() {
    None => Matrix3f::identity()
    Some(determinant) => {
      let det = (1.0 : Float) / determinant
      let a = v[0][0]
      let b = v[0][1]
      let c = v[0][2]
      let d = v[1][0]
      let e = v[1][1]
      let f = v[1][2]
      let g = v[2][0]
      let h = v[2][1]
      let i = v[2][2]
      {
        v: [
          [(e * i - f * h) * det, (c * h - b * i) * det, (b * f - c * e) * det],
          [(f * g - d * i) * det, (a * i - c * g) * det, (c * d - a * f) * det],
          [(d * h - e * g) * det, (b * g - a * h) * det, (a * e - b * d) * det],
        ],
      }
    }
  }
}

///|
pub fn Matrix3d::mul_vector(self : Matrix3d, other : Vector3d) -> Vector3d {
  let v = self.v
  let o = other.v
  let x = v[0][1] * o[1] + v[0][2] * o[2] + v[0][0] * o[0]
  let y = v[1][0] * o[0] + v[1][1] * o[1] + v[1][2] * o[2]
  let z = v[2][0] * o[0] + v[2][1] * o[1] + v[2][2] * o[2]
  { v: [x, y, z], }
}

///|
pub fn Matrix3f::mul_vector(self : Matrix3f, other : Vector3f) -> Vector3f {
  let v = self.v
  let o = other.v
  let x = v[0][1] * o[1] + v[0][2] * o[2] + v[0][0] * o[0]
  let y = v[1][0] * o[0] + v[1][1] * o[1] + v[1][2] * o[2]
  let z = v[2][0] * o[0] + v[2][1] * o[1] + v[2][2] * o[2]
  { v: [x, y, z], }
}

///|
/// `Matrix3d::mat_mul` (`mlaf(mlaf(a0 * b0, a1, b1), a2, b2)`).
pub fn Matrix3d::mat_mul(self : Matrix3d, other : Matrix3d) -> Matrix3d {
  let r = Matrix3d::zero()
  for i in 0..<3 {
    for j in 0..<3 {
      r.v[i][j] = self.v[i][0] * other.v[0][j] +
        self.v[i][1] * other.v[1][j] +
        self.v[i][2] * other.v[2][j]
    }
  }
  r
}

///|
pub fn Matrix3f::mat_mul(self : Matrix3f, other : Matrix3f) -> Matrix3f {
  let r = Matrix3f::zero()
  for i in 0..<3 {
    for j in 0..<3 {
      r.v[i][j] = self.v[i][0] * other.v[0][j] +
        self.v[i][1] * other.v[1][j] +
        self.v[i][2] * other.v[2][j]
    }
  }
  r
}

///|
pub fn Matrix3d::to_f32(self : Matrix3d) -> Matrix3f {
  let r = Matrix3f::zero()
  for i in 0..<3 {
    for j in 0..<3 {
      r.v[i][j] = Float::from_double(self.v[i][j])
    }
  }
  r
}

///|
pub fn Matrix3f::to_f64(self : Matrix3f) -> Matrix3d {
  let r = Matrix3d::zero()
  for i in 0..<3 {
    for j in 0..<3 {
      r.v[i][j] = self.v[i][j].to_double()
    }
  }
  r
}
