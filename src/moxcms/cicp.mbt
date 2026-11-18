// Port of moxcms 0.9.0 `cicp.rs` (the parts the ICC parser and the transfer
// tables reach: the enums, their conversions and `create_rec709_parametric`).

///|
#derive(Eq, Debug)
pub(all) enum CicpColorPrimaries {
  Reserved
  Bt709
  Unspecified
  Bt470M
  Bt470Bg
  Bt601
  Smpte240
  GenericFilm
  Bt2020
  Xyz
  Smpte431
  Smpte432
  Ebu3213
}

///|
pub fn CicpColorPrimaries::try_from(value : Int32) -> CicpColorPrimaries {
  match value {
    1 => Bt709
    2 => Unspecified
    4 => Bt470M
    5 => Bt470Bg
    6 => Bt601
    7 => Smpte240
    8 => GenericFilm
    9 => Bt2020
    10 => Xyz
    11 => Smpte431
    12 => Smpte432
    22 => Ebu3213
    // Values 0, 3, 13–21, 23–255 are all reserved.
    _ => Reserved
  }
}

///|
#derive(Eq, Debug)
pub(all) enum TransferCharacteristics {
  Reserved
  Bt709
  Unspecified
  Bt470M
  Bt470Bg
  Bt601
  Smpte240
  Linear
  Log100
  Log100sqrt10
  Iec61966
  Bt1361
  Srgb
  Bt202010bit
  Bt202012bit
  Smpte2084
  Smpte428
  Hlg
}

///|
pub fn TransferCharacteristics::try_from(
  value : Int32,
) -> TransferCharacteristics {
  match value {
    1 => Bt709
    2 => Unspecified
    4 => Bt470M
    5 => Bt470Bg
    6 => Bt601
    7 => Smpte240
    8 => Linear
    9 => Log100
    10 => Log100sqrt10
    11 => Iec61966
    12 => Bt1361
    13 => Srgb
    14 => Bt202010bit
    15 => Bt202012bit
    16 => Smpte2084
    17 => Smpte428
    18 => Hlg
    // 0 | 3 | 19..=255
    _ => Reserved
  }
}

///|
pub fn TransferCharacteristics::has_transfer_curve(
  self : TransferCharacteristics,
) -> Bool {
  self != Reserved && self != Unspecified
}

///|
#derive(Eq, Debug)
pub(all) enum MatrixCoefficients {
  Identity
  Bt709
  Unspecified
  Reserved
  Fcc
  Bt470Bg
  Smpte170m
  Smpte240m
  YCgCo
  Bt2020Ncl
  Bt2020Cl
  Smpte2085
  ChromaticityDerivedNCL
  ChromaticityDerivedCL
  ICtCp
  IPtC2
  YCgCoRe
  YCgCoRo
}

///|
pub fn MatrixCoefficients::try_from(
  value : Int32,
) -> MatrixCoefficients raise CmsError {
  match value {
    0 => Identity
    1 => Bt709
    2 => Unspecified
    3 => Reserved
    4 => Fcc
    5 => Bt470Bg
    6 => Smpte170m
    7 => Smpte240m
    8 => YCgCo
    9 => Bt2020Ncl
    10 => Bt2020Cl
    11 => Smpte2085
    12 => ChromaticityDerivedNCL
    13 => ChromaticityDerivedCL
    14 => ICtCp
    15 => IPtC2
    16 => YCgCoRe
    17 => YCgCoRo
    _ => raise InvalidCicp
  }
}

///|
fn create_rec709_parametric() -> FixedArray[Float] {
  let pow_exp : Float = 0.45
  let g : Float = (1.0 : Float) / pow_exp
  let b = Float::from_double(0.09929682680944 / 1.09929682680944)
  let c : Float = (1.0 : Float) / (4.5 : Float)
  let d = Float::from_double(4.5 * 0.018053968510807)
  let a = Float::from_double(1.0 / 1.09929682680944)
  [g, a, b, c, d]
}
