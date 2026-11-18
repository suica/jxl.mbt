///|
/// Generated from `grayscale` (frame 0) with jxl-oxide.
test "vardct sections of grayscale match jxl-oxide" {
  let lf_global_hex =
    #|550f0000a8501965dce0e55ccf971f3a2ca66d5c6768ab6d0b4b120990792b1780f7040f83c14c0a
    #|0adcaa92372d6738ac1c9fa363632363c68933973715190542d86151115a54c01014340805213161
    #|402804c4044148488544c048501149109091e74310b6daedbccfb7273046f41bf6832928eb97f279
    #|30200e88efe71b77d75d9d3cb277bd77fff716e81150de1e42670cf1b897ab60323e4b67af4f70ae
    #|a6f083be636fe7ef84a7a03763e01778f4fead66c5df8d7046888bffb6e7c2c657f224208bd0e47a
    #|6a3f0ddb7aaf85d08fcc1050b5c620b020c8a1a760fe5047ebff949fc0578e200e07c5d60db7e2fe
    #|22cfda68383f6d6ff0ef12e7c357d6e8514daec893c789d0566f4947dc179d668af0b1c7a30e6dbe
    #|a9b9cbd7d0168de6df9754971c4f0027ba8e29efbb96bb968e1613bf80deb5afcf96ef06ee86ef2e
    #|bce465572f0f5f2f562f379facde5bc89f5f75fe1daf0d8f900f60bf9d56fc001b2e38a659dfa6ee
    #|b2a8288b64ed2ca242bd288b64ed2ca242bd288b64ed2ca242bd288b64ed2ca242bd288b64ed2ca2
    #|42bd288b64ed2ca242bd288b64ed2ca242bd280b4c6d9c68f16586c528c66bfe1fe01d66fd732c96
    #|10eed0cc3058a1c51a01e66112c24c076e0710423012e710d90131520d28e01f28e2114018f6147e
    #|0eaeca31e1dbb724c28ae23b1db1b5a16f03b0b266d75fbd9755adf77fdf60fa1c30bdfab5c3ffd5
    #|0e9f1e140db93a2dd2a58d92ec07b923e540382d19753719aa093de414404299b1cda358812837cb
    #|170807285ad8ffc2e9004066a81653d6d169ca6c7985f4880f55078e22089c6836292850d96d543c
    #|9c18860624318ad4d83900749108a0f43da00ff51a4a4ae9dd1b654fef660ebe1ae557fb8131b22d
    #|1996390327f9d8a250b85ed436afbbaeff5cd46f3de940805b4a964ed3268f49f27eefa84a4ab01b
    #|c7d6903369ae80cb4f2bccb5981c932000decbe5f4f2d69c33b8fb5d7ecd55213008ba4e4dc545f5
    #|4d21d13448bfb8fb6d88018a972d87d19bbd642448ea36e6093362138aafb25dbc725a08c36ad3f7
    #|459a5ea4fb6d8899d0a2d16804c7e53d19d055c6a4d26ec8291775389be99e0892c0eb8545001570
    #|6eac0d4ac6022e551fd775c0c84f1af024
  let lf_group_hex = lf_global_hex
  let hf_global_hex = lf_global_hex
  let pass_group_hex = lf_global_hex
  check_sections(
    hex_to_bytes(lf_global_hex),
    hex_to_bytes(lf_group_hex),
    hex_to_bytes(hf_global_hex),
    hex_to_bytes(pass_group_hex),
    {
      lf_global_end: 497,
      lf_group_start: 497,
      lf_group_end: 4381,
      hf_global_start: 4381,
      hf_global_end: 4856,
      pass_group_start: 4856,
      pass_group_end: 6536,
      node_limit: 8524,
      bits_per_sample: 8,
      lf_width: 200,
      lf_height: 200,
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
      quantizer: (4587, 16),
      num_block_clusters: 15,
      block_ctx_map_hash: 385839685U,
      qf_thresholds: [],
      lf_thresholds: [[], [], []],
      lf_chan_corr: (84, 0U, 1065353216U, 128, 128),
      has_global_tree: true,
      extra_precision: 0,
      lf_quant_hashes: [3250204691U, 3955092831U, 3955092831U],
      x_from_y_hash: 1768495365U,
      b_from_y_hash: 1768495365U,
      block_info_hash: 1254881745U,
      epf_sigma_hash: 1330976541U,
      dequant_hash: 241701352U,
      num_hf_presets: 1,
      hf_coeff_hashes: [73013957U, 1943474813U, 73013957U],
      block_w: 25,
      block_h: 25,
    },
  )
}
