///|
/// Varblock grid information.
#derive(Eq, Debug)
pub(all) enum BlockInfo {
  /// The block is not initialized yet.
  Uninit
  /// The block is occupied by a varblock.
  Occupied
  /// The block is the top-left block of a varblock.
  Data(dct_select~ : TransformType, hf_mul~ : Int32)
}

///|
pub impl Default for BlockInfo with fn default() {
  Uninit
}

///|
fn BlockInfo::is_occupied(self : BlockInfo) -> Bool {
  !(self is Uninit)
}
