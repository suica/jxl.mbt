// Port of jxl-color/src/lib.rs.
//
// This package provides a set of functions related to color encodings defined by the JPEG XL
// specification. The colour encoding header types live in `suica/jxl/image` (as in upstream
// `jxl_image::color`) and are re-exported here (`pub use jxl_image::color::*`).

///|
pub using @image {
  type ColourEncoding,
  type EnumColourEncoding,
  type Customxy,
  type ToneMapping,
  type ColourSpace,
  type WhitePoint,
  type Primaries,
  type RenderingIntent,
  type TransferFunction,
  type OpsinInverseMatrix,
}
