///|
/// Varblock transform types.
#derive(Eq, Debug, Hash)
pub(all) enum TransformType {
  Dct8
  Hornuss
  Dct2
  Dct4
  Dct16
  Dct32
  Dct16x8
  Dct8x16
  Dct32x8
  Dct8x32
  Dct32x16
  Dct16x32
  Dct4x8
  Dct8x4
  Afv0
  Afv1
  Afv2
  Afv3
  Dct64
  Dct64x32
  Dct32x64
  Dct128
  Dct128x64
  Dct64x128
  Dct256
  Dct256x128
  Dct128x256
}

///|
let transform_type_list : FixedArray[TransformType] = [
  Dct8,
  Hornuss,
  Dct2,
  Dct4,
  Dct16,
  Dct32,
  Dct16x8,
  Dct8x16,
  Dct32x8,
  Dct8x32,
  Dct32x16,
  Dct16x32,
  Dct4x8,
  Dct8x4,
  Afv0,
  Afv1,
  Afv2,
  Afv3,
  Dct64,
  Dct64x32,
  Dct32x64,
  Dct128,
  Dct128x64,
  Dct64x128,
  Dct256,
  Dct256x128,
  Dct128x256,
]

///|
/// `TryFrom<u8> for TransformType`.
pub fn TransformType::try_from(
  value : Int32,
) -> TransformType raise @bitstream.JxlError {
  if value >= 0 && value < transform_type_list.length() {
    transform_type_list[value]
  } else {
    raise @bitstream.InvalidEnum("TransformType", value.reinterpret_as_uint())
  }
}

///|
/// The `repr(u8)` value of the transform type.
pub fn TransformType::to_int(self : TransformType) -> Int32 {
  match self {
    Dct8 => 0
    Hornuss => 1
    Dct2 => 2
    Dct4 => 3
    Dct16 => 4
    Dct32 => 5
    Dct16x8 => 6
    Dct8x16 => 7
    Dct32x8 => 8
    Dct8x32 => 9
    Dct32x16 => 10
    Dct16x32 => 11
    Dct4x8 => 12
    Dct8x4 => 13
    Afv0 => 14
    Afv1 => 15
    Afv2 => 16
    Afv3 => 17
    Dct64 => 18
    Dct64x32 => 19
    Dct32x64 => 20
    Dct128 => 21
    Dct128x64 => 22
    Dct64x128 => 23
    Dct256 => 24
    Dct256x128 => 25
    Dct128x256 => 26
  }
}

///|
/// Returns the size of the transform type, in 8x8 blocks.
pub fn TransformType::dct_select_size(self : TransformType) -> (Int32, Int32) {
  match self {
    Dct8
    | Hornuss
    | Dct2
    | Dct4
    | Dct4x8
    | Dct8x4
    | Afv0
    | Afv1
    | Afv2
    | Afv3 => (1, 1)
    Dct16 => (2, 2)
    Dct32 => (4, 4)
    Dct16x8 => (1, 2)
    Dct8x16 => (2, 1)
    Dct32x8 => (1, 4)
    Dct8x32 => (4, 1)
    Dct32x16 => (2, 4)
    Dct16x32 => (4, 2)
    Dct64 => (8, 8)
    Dct64x32 => (4, 8)
    Dct32x64 => (8, 4)
    Dct128 => (16, 16)
    Dct128x64 => (8, 16)
    Dct64x128 => (16, 8)
    Dct256 => (32, 32)
    Dct256x128 => (16, 32)
    Dct128x256 => (32, 16)
  }
}

///|
fn TransformType::dequant_matrix_param_index(self : TransformType) -> Int32 {
  match self {
    Dct8 => 0
    Hornuss => 1
    Dct2 => 2
    Dct4 => 3
    Dct16 => 4
    Dct32 => 5
    Dct16x8 | Dct8x16 => 6
    Dct32x8 | Dct8x32 => 7
    Dct32x16 | Dct16x32 => 8
    Dct4x8 | Dct8x4 => 9
    Afv0 | Afv1 | Afv2 | Afv3 => 10
    Dct64 => 11
    Dct64x32 | Dct32x64 => 12
    Dct128 => 13
    Dct128x64 | Dct64x128 => 14
    Dct256 => 15
    Dct256x128 | Dct128x256 => 16
  }
}

///|
fn TransformType::dequant_matrix_size(self : TransformType) -> (Int32, Int32) {
  match self {
    Dct8
    | Hornuss
    | Dct2
    | Dct4
    | Dct4x8
    | Dct8x4
    | Afv0
    | Afv1
    | Afv2
    | Afv3 => (8, 8)
    Dct16 => (16, 16)
    Dct32 => (32, 32)
    Dct16x8 | Dct8x16 => (16, 8)
    Dct32x8 | Dct8x32 => (32, 8)
    Dct32x16 | Dct16x32 => (32, 16)
    Dct64 => (64, 64)
    Dct64x32 | Dct32x64 => (64, 32)
    Dct128 => (128, 128)
    Dct128x64 | Dct64x128 => (128, 64)
    Dct256 => (256, 256)
    Dct256x128 | Dct128x256 => (256, 128)
  }
}

///|
fn TransformType::order_id(self : TransformType) -> Int32 {
  match self {
    Dct8 => 0
    Hornuss | Dct2 | Dct4 | Dct4x8 | Dct8x4 | Afv0 | Afv1 | Afv2 | Afv3 => 1
    Dct16 => 2
    Dct32 => 3
    Dct16x8 | Dct8x16 => 4
    Dct32x8 | Dct8x32 => 5
    Dct32x16 | Dct16x32 => 6
    Dct64 => 7
    Dct64x32 | Dct32x64 => 8
    Dct128 => 9
    Dct128x64 | Dct64x128 => 10
    Dct256 => 11
    Dct256x128 | Dct128x256 => 12
  }
}

///|
/// Returns whether DCT coefficients should be transposed.
pub fn TransformType::need_transpose(self : TransformType) -> Bool {
  match self {
    Hornuss | Dct2 | Dct4 | Dct4x8 | Dct8x4 | Afv0 | Afv1 | Afv2 | Afv3 => false
    _ => {
      let (w, h) = self.dct_select_size()
      h >= w
    }
  }
}
