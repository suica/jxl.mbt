// STUB: placeholder until the real pxfm port lands (strict/moxcms-pxfm).

///|
pub fn f_pow(x : Double, y : Double) -> Double {
  @math.pow(x, y)
}

///|
pub fn f_exp(x : Double) -> Double {
  @math.exp(x)
}

///|
pub fn f_log(x : Double) -> Double {
  @math.ln(x)
}

///|
pub fn f_exp10(x : Double) -> Double {
  @math.pow(10.0, x)
}

///|
pub fn f_log10(x : Double) -> Double {
  @math.log10(x)
}

///|
pub fn f_powf(x : Float, y : Float) -> Float {
  Float::from_double(@math.pow(x.to_double(), y.to_double()))
}

///|
pub fn dirty_powf(x : Float, y : Float) -> Float {
  Float::from_double(@math.pow(x.to_double(), y.to_double()))
}

///|
pub fn f_cbrtf(x : Float) -> Float {
  Float::from_double(@math.cbrt(x.to_double()))
}
