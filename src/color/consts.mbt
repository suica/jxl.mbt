// Constants used by the various colorspaces (port of jxl-color/src/consts.rs).
//
// Values are in xy-chromaticity coordinates.

///|
/// CIE illuminant D65.
///
/// This is the white point mainly used in the sRGB colorspace.
pub let illuminant_d65 : FixedArray[Float] = [0.3127, 0.329]

///|
/// CIE illuminant E (equal-energy).
pub let illuminant_e : FixedArray[Float] = [
  (1.0 : Float) / 3.0,
  (1.0 : Float) / 3.0,
]

///|
/// DCI-P3 illuminant.
pub let illuminant_dci : FixedArray[Float] = [0.314, 0.351]

///|
/// CIE illuminant D50.
///
/// xy-chromaticity value is computed so that the resulting `chad` tag matches that of libjxl.
let illuminant_d50 : FixedArray[Float] = [0.345669, 0.358496]

///|
/// Primaries used by the sRGB colorspace.
pub let primaries_srgb : FixedArray[FixedArray[Float]] = [
  [0.639998686, 0.330010138],
  [0.300003784, 0.600003357],
  [0.150002046, 0.059997204],
]

///|
/// Primaries specified in ITU-R BT.2100-2.
pub let primaries_bt2100 : FixedArray[FixedArray[Float]] = [
  [0.708, 0.292],
  [0.170, 0.797],
  [0.131, 0.046],
]

///|
/// Primaries specified in SMPTE ST 428-1.
pub let primaries_p3 : FixedArray[FixedArray[Float]] = [
  [0.680, 0.320],
  [0.265, 0.690],
  [0.150, 0.060],
]
