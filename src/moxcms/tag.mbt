// Port of moxcms 0.9.0 `tag.rs`.

///|
const TAG_SIZE : Int32 = 12

///|
/// Big-endian four character code.
fn fourcc(s : String) -> UInt32 {
  let mut v = 0U
  for i in 0..<4 {
    v = (v << 8) | (s[i].to_int().reinterpret_as_uint() & 0xFF)
  }
  v
}

///|
#derive(Eq, Debug)
priv enum Tag {
  RedXyz
  GreenXyz
  BlueXyz
  RedToneReproduction
  GreenToneReproduction
  BlueToneReproduction
  GreyToneReproduction
  MediaWhitePoint
  CodeIndependentPoints
  ChromaticAdaptation
  BlackPoint
  DeviceToPcsLutPerceptual
  DeviceToPcsLutColorimetric
  DeviceToPcsLutSaturation
  PcsToDeviceLutPerceptual
  PcsToDeviceLutColorimetric
  PcsToDeviceLutSaturation
  ProfileDescription
  Copyright
  ViewingConditionsDescription
  DeviceManufacturer
  DeviceModel
  Gamut
  Luminance
  Measurement
  Chromaticity
  ObserverConditions
  CharTarget
  Technology
  CalibrationDateTime
}

///|
fn Tag::try_from(value : UInt32) -> Tag raise CmsError {
  let table : FixedArray[(String, Tag)] = [
    ("rXYZ", RedXyz),
    ("gXYZ", GreenXyz),
    ("bXYZ", BlueXyz),
    ("rTRC", RedToneReproduction),
    ("gTRC", GreenToneReproduction),
    ("bTRC", BlueToneReproduction),
    ("kTRC", GreyToneReproduction),
    ("wtpt", MediaWhitePoint),
    ("cicp", CodeIndependentPoints),
    ("chad", ChromaticAdaptation),
    ("bkpt", BlackPoint),
    ("A2B0", DeviceToPcsLutPerceptual),
    ("A2B1", DeviceToPcsLutColorimetric),
    ("A2B2", DeviceToPcsLutSaturation),
    ("B2A0", PcsToDeviceLutPerceptual),
    ("B2A1", PcsToDeviceLutColorimetric),
    ("B2A2", PcsToDeviceLutSaturation),
    ("desc", ProfileDescription),
    ("cprt", Copyright),
    ("vued", ViewingConditionsDescription),
    ("dmnd", DeviceManufacturer),
    ("dmdd", DeviceModel),
    ("gamt", Gamut),
    ("lumi", Luminance),
    ("meas", Measurement),
    ("chrm", Chromaticity),
    ("view", ObserverConditions),
    ("targ", CharTarget),
    ("tech", Technology),
    ("calt", CalibrationDateTime),
  ]
  for entry in table {
    if fourcc(entry.0) == value {
      return entry.1
    }
  }
  raise UnknownTag(value)
}

///|
#derive(Eq, Debug)
priv enum TagTypeDefinition {
  Text
  MultiLocalizedUnicode
  Description
  MabLut
  MbaLut
  ParametricToneCurve
  LutToneCurve
  Xyz
  MultiProcessElement
  DefViewingConditions
  Signature
  Cicp
  DateTime
  S15Fixed16Array
  U8Array
  U16Fixed16Array
  U16Array
  U32Array
  U64Array
  Measurement
  NotAllowed
}

///|
fn TagTypeDefinition::from(value : UInt32) -> TagTypeDefinition {
  let table : FixedArray[(String, TagTypeDefinition)] = [
    ("mluc", MultiLocalizedUnicode),
    ("desc", Description),
    ("text", Text),
    ("mAB ", MabLut),
    ("mBA ", MbaLut),
    ("para", ParametricToneCurve),
    ("curv", LutToneCurve),
    ("XYZ ", Xyz),
    ("mpet", MultiProcessElement),
    ("view", DefViewingConditions),
    ("sig ", Signature),
    ("cicp", Cicp),
    ("dtim", DateTime),
    ("meas", Measurement),
    ("sf32", S15Fixed16Array),
    ("uf32", U16Fixed16Array),
    ("ui16", U16Array),
    ("ui32", U32Array),
    ("ui64", U64Array),
    ("ui08", U8Array),
  ]
  for entry in table {
    if fourcc(entry.0) == value {
      return entry.1
    }
  }
  NotAllowed
}
