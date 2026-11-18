///|
/// Generated from `issue_24` (frame 0) with jxl-oxide.
test "vardct sections of issue_24 match jxl-oxide" {
  let lf_global_hex =
    #|af1228010050a132cab8c1cbb99e2f3f74584cdbb8ced056db16963036db0b838484c38621de1c22
    #|0c11432509
  let lf_group_hex = lf_global_hex
  let hf_global_hex = lf_global_hex
  let pass_group_hex = lf_global_hex
  check_sections(
    hex_to_bytes(lf_global_hex),
    hex_to_bytes(lf_group_hex),
    hex_to_bytes(hf_global_hex),
    hex_to_bytes(pass_group_hex),
    {
      lf_global_end: 300,
      lf_group_start: 300,
      lf_group_end: 342,
      hf_global_start: 342,
      hf_global_end: 360,
      pass_group_start: 360,
      pass_group_end: 360,
      node_limit: 1024,
      bits_per_sample: 8,
      lf_width: 1,
      lf_height: 1,
      jpeg_upsampling: [0, 0, 0],
      epf: Some(
        (
          Float::reinterpret_from_uint(1055622431U),
          [
            Float::reinterpret_from_uint(0U),
            Float::reinterpret_from_uint(1041385765U),
            Float::reinterpret_from_uint(1049774373U),
            Float::reinterpret_from_uint(1054567863U),
            Float::reinterpret_from_uint(1058162981U),
            Float::reinterpret_from_uint(1060559726U),
            Float::reinterpret_from_uint(1062956471U),
            Float::reinterpret_from_uint(1065353216U),
          ],
        ),
      ),
      num_groups: 1,
      num_lf_groups: 1,
      group_dim: 256,
      num_passes: 1,
      coeff_shift: 0,
      lf_dequant: [1023410176U, 1048576000U, 1056964608U],
      quantizer: (8790, 10),
      num_block_clusters: 15,
      block_ctx_map_hash: 385839685U,
      qf_thresholds: [],
      lf_thresholds: [[], [], []],
      lf_chan_corr: (84, 0U, 1065353216U, 128, 128),
      has_global_tree: true,
      extra_precision: 1,
      lf_quant_hashes: [2365936695U, 84696351U, 84696351U],
      x_from_y_hash: 84696351U,
      b_from_y_hash: 84696351U,
      block_info_hash: 53630272U,
      epf_sigma_hash: 520913324U,
      dequant_hash: 241701352U,
      num_hf_presets: 1,
      hf_coeff_hashes: [3755895493U, 3755895493U, 3755895493U],
      block_w: 1,
      block_h: 1,
    },
  )
}
