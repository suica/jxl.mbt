///|
fn gen_tree(
  rng : Rng,
  depth : Int32,
  next_leaf : Ref[Int32],
  uniform~ : Bool = false,
) -> MaTreeNode {
  if depth == 0 || rng.range(0, 4) == 0 {
    let id = next_leaf.val
    next_leaf.val += 1
    if uniform {
      return MaTreeNode::Leaf({
        cluster: id,
        predictor: Gradient,
        offset: 0,
        multiplier: 1,
      })
    }
    return MaTreeNode::Leaf({
      cluster: id,
      predictor: all_predictors[rng.range(0, 13)],
      offset: rng.range(-2, 2),
      multiplier: 1,
    })
  }
  let props = if uniform {
    [9, 9, 9, 0]
  } else {
    [0, 1, 9, 9, 9, 6, 6, 15, 16, 17, 21, 2, 3]
  }
  let property = props[rng.range(0, props.length() - 1)]
  let value = rng.range(-6, 6)
  let left = gen_tree(rng, depth - 1, next_leaf, uniform~)
  let right = gen_tree(rng, depth - 1, next_leaf, uniform~)
  Decision(property~, value~, left~, right~)
}

///|
fn naive_eval(
  node : MaTreeNode,
  channel : Int32,
  stream_idx : Int32,
  state : PredictorState,
) -> MaTreeLeafClustered {
  let mut node = node
  while true {
    match node {
      Leaf(leaf) => return leaf
      Decision(property~, value~, left~, right~) => {
        let v = if property == 0 {
          channel
        } else if property == 1 {
          stream_idx
        } else {
          state.get_property(property)
        }
        node = if v > value { left } else { right }
      }
    }
  }
  panic()
}

///|
/// Per-tree hashes of the leaves chosen by upstream's flattened tree, and the
/// number of samples where upstream's flattened tree disagrees with a naive
/// evaluation of the tree (upstream's table compilation does not clamp a
/// subtree's range to its parent's, so redundant same-property decisions with
/// out-of-range values can be resolved differently; this port mirrors it).
let ma_reference : Array[UInt32] = [
  3903639511U, 2393586210U, 4147860112U, 3963512581U, 2873315363U, 3727779064U, 3963512581U,
  2953204536U, 1010656617U, 2188708830U, 3963512581U, 3963512581U, 1253106034U, 2552011344U,
  3627415251U, 3963512581U, 1419399901U, 832647905U, 4040812759U, 3963512581U, 3963512581U,
  2123972447U, 2288720744U, 3963512581U, 3328754424U, 2130694551U, 3269658386U, 1691881386U,
  3963512581U, 2733548950U, 830434482U, 1609792393U, 3963512581U, 4058627203U, 1061866367U,
  373726236U, 1251447616U, 2067063979U, 3213641405U, 259784316U, 3963512581U, 1173295921U,
  1184098234U, 727152090U, 4034274228U, 1787441353U, 3963512581U, 3963512581U, 848817519U,
  3963512581U, 3963512581U, 2004556708U, 3073029595U, 550248909U, 264676802U, 3963512581U,
  1053189091U, 3963512581U, 1390325111U, 3269198895U, 3963512581U, 3841365918U, 3963512581U,
  2932082732U, 3963512581U, 3963512581U, 2547410816U, 249123413U, 104312374U, 3947438099U,
  392245985U, 2374734262U, 1220716085U, 1176848374U, 659465229U, 3963512581U, 1618039931U,
  3584806665U, 3963512581U, 3856999021U, 4194792310U, 1809689116U, 3963512581U, 2681380075U,
  2742244502U, 1816525933U, 3963512581U, 1127420907U, 3348229046U, 3702132288U, 3472084547U,
  3117313993U, 300657482U, 1551020583U, 3137970941U, 1012934401U, 3726955295U, 3963512581U,
  2977644600U, 1403626713U, 3863769147U, 4002167006U, 694954405U, 1123206236U, 2953874643U,
  3963512581U, 1267272126U, 3963512581U, 3076841745U, 1929584207U, 3369516232U, 4056589072U,
  3963512581U, 1414565027U, 3874619482U, 3963512581U, 1040766263U, 2723238917U, 3963512581U,
  3032835617U, 3963512581U, 2037470111U, 2983648943U, 464850639U, 2891757006U, 9023033U,
  3963512581U, 2723304797U, 3963512581U, 444201114U, 1612021563U, 3377986836U, 2541082962U,
  1472467872U, 3829656654U, 3963512581U, 2353056298U, 3963512581U, 463243824U, 3963512581U,
  1812187079U, 3963512581U, 3963512581U, 3227274240U, 3827917883U, 3963512581U, 158696736U,
  387757442U, 2462005259U, 1061795956U, 2498421979U, 3914972097U, 996251126U, 3963512581U,
  417791527U, 991866888U, 1255557357U, 1094709128U, 3963512581U, 1737026087U, 3963512581U,
  3963512581U, 3963512581U, 3840493872U, 740119926U, 4004460910U, 1371235097U, 1759965413U,
  1808469683U, 2901815456U, 3963512581U, 3963512581U, 1649564726U, 3963512581U, 565701397U,
  2464344840U, 2074209388U, 13280279U, 788650230U, 1558770563U, 1105063820U, 592434205U,
  1521944175U, 1427469620U, 3608968538U, 51967823U, 2706304667U, 3149036411U, 314411577U,
  1151207331U, 3698150005U, 3963512581U, 1941808838U, 3527193945U, 3963512581U, 3217568043U,
  2894667678U, 1819867363U, 530382077U, 1173434170U, 3187510564U, 1122548749U, 2212197276U,
  3963512581U, 3839811621U, 1454237918U, 242182103U, 500312545U, 2343340870U, 227851840U,
  3963512581U, 3963512581U, 2687291778U, 3878268983U, 1292975805U, 1238731222U, 3216913773U,
  3963512581U, 1265209638U, 1601787161U, 2053900570U, 3963512581U, 245545618U, 1961089583U,
  3442460380U, 463680027U, 2969534394U, 530300330U, 3025479969U, 544928251U, 3152039285U,
  3712449795U, 3256028022U, 2348218383U, 354972245U, 3332840051U, 2234663098U, 3963512581U,
  1043954998U, 2658900782U, 3963512581U, 3963512581U, 1242479088U, 3963512581U, 3323552661U,
  3292917917U, 3023615760U, 3963512581U, 1433553244U, 455088917U, 425967397U, 1061081844U,
  3963512581U, 3601868572U, 3963512581U, 815682491U, 3205326600U, 1811227658U, 810682468U,
  926020791U, 2760954058U, 3498864991U, 1206181806U, 2998174611U, 1740338706U, 1949101781U,
  3963512581U, 3963512581U, 3286178101U, 3963512581U, 3963512581U, 3963512581U, 1755903146U,
  3963512581U, 3854723221U, 1757705978U, 3963512581U, 3963512581U, 408476071U, 2990311301U,
  1741610749U, 3840100823U, 900180276U, 3963512581U, 3963512581U, 440632699U, 3712082027U,
  444122970U, 3723830718U, 298426692U, 1158944629U, 1033899554U, 4035827069U, 3963512581U,
  801232660U, 2785291360U, 323823256U, 3327495097U, 628588639U, 1188181618U,
]

///|
test "flattened MA tree matches upstream" {
  let rng = { state: 12345UL, }
  let mut tables = 0
  let mut simple_tables = 0
  let mut mismatches = 0
  for t in 0..<300 {
    let tree = gen_tree(rng, 2 + t % 6, Ref(0))
    let hash = { h: 2166136261U, }
    for _ in 0..<20 {
      let channel = rng.range(0, 3)
      let stream_idx = rng.range(0, 3)
      let prev_channels = rng.range(0, 3)
      let prev = Array::makei(prev_channels, fn(_) {
        rand_grid(rng, 1, 1, -8, 8).as_subgrid()
      })
      let flat = FlatMaTree::new(
        tree.flatten(channel, stream_idx, prev_channels),
      )
      if flat.nodes[0] is Table(_) {
        tables += 1
      }
      let table = flat.simple_table()
      if table is Some(_) {
        simple_tables += 1
      }
      let state = PredictorState::new()
      state.reset(1, prev, None)
      for _ in 0..<20 {
        for p in 2..<16 {
          state.prop_cache[p] = rng.range(-9, 9)
        }
        let leaf = flat.get_leaf(state)
        if leaf != naive_eval(tree, channel, stream_idx, state) {
          mismatches += 1
        }
        hash.add(leaf.cluster)
        if table is Some(table) {
          let v = state.get_property(table.decision_prop)
          assert_eq(
            cluster_from_table(v, table.value_base, table.cluster_table),
            leaf.cluster,
          )
          assert_eq(table.predictor, leaf.predictor)
        }
      }
    }
    assert_eq(hash.h, ma_reference[t], msg="tree \{t}")
  }
  assert_eq(mismatches, 624)
  assert_eq(tables, 137)
  ignore(simple_tables)
}

///|
test "channel shift sizes" {
  let up : FixedArray[Int32] = [1, 0, 0]
  let s0 = ChannelShift::from_jpeg_upsampling(up, 0)
  let s1 = ChannelShift::from_jpeg_upsampling(up, 1)
  assert_eq(s0.shift_size((15, 9)), (16, 10))
  assert_eq(s1.shift_size((15, 9)), (8, 5))
  assert_eq((s1.hshift(), s1.vshift()), (1, 1))
  assert_eq(ChannelShift::from_shift(3).shift_size((17, 8)), (3, 1))
  assert_eq(ChannelShift::Raw(1, 2).shift_size((5, 5)), (3, 2))
}

///|
test "default squeeze params and channel info" {
  let channels : ModularChannels = {
    info: [
      ModularChannelInfo::new(40, 20, ChannelShift::from_shift(0)),
      ModularChannelInfo::new(40, 20, ChannelShift::from_shift(0)),
      ModularChannelInfo::new(40, 20, ChannelShift::from_shift(0)),
    ],
    nb_meta_channels: 0,
  }
  let sq : Squeeze = { num_sq: 0, sp: [], }
  sq.set_default_params(channels)
  let grids = Array::makei(3, fn(_) {
    TransformedGrid::from(@grid.Grid::new(40, 20, 0).as_subgrid())
  })
  sq.transform_channel_info(channels, Some(grids))
  assert_eq(channels.info.length(), grids.length())
  for i, info in channels.info {
    assert_eq(info.width, grids[i].grid.width)
    assert_eq(info.height, grids[i].grid.height)
  }
  // first channel squeezed 3 times horizontally and 2 times vertically
  assert_eq(channels.info[0].width, 5)
  assert_eq(channels.info[0].height, 5)
  assert_eq(channels.info[0].hshift, 3)
  assert_eq(channels.info[0].vshift, 2)
  assert_eq(sq.sp.length(), 7)
  // forward-squeeze + inverse round trip of zeros keeps zeros and sizes
  sq.inverse(grids)
  assert_eq(grids.length(), 3)
  for g in grids {
    assert_eq(g.grid.width, 40)
    assert_eq(g.grid.height, 20)
  }
}

///|
test "simple MA table agrees with flattened tree" {
  let rng = { state: 777UL, }
  let mut simple_tables = 0
  for t in 0..<300 {
    let tree = gen_tree(rng, 3 + t % 5, Ref(0), uniform=true)
    let channel = rng.range(0, 3)
    let stream_idx = rng.range(0, 3)
    let flat = FlatMaTree::new(tree.flatten(channel, stream_idx, 0))
    guard flat.simple_table() is Some(table) else { continue }
    simple_tables += 1
    let state = PredictorState::new()
    state.reset(1, [], None)
    for _ in 0..<50 {
      for p in 2..<16 {
        state.prop_cache[p] = rng.range(-9, 9)
      }
      let leaf = flat.get_leaf(state)
      let v = state.get_property(table.decision_prop)
      assert_eq(
        cluster_from_table(v, table.value_base, table.cluster_table),
        leaf.cluster,
      )
    }
  }
  assert_true(simple_tables > 10)
}
