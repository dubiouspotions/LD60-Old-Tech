extends GutTest

const LOG := preload("res://data/bridge/log.tres")
const ROPE := preload("res://data/bridge/rope.tres")
const SUPPORT := preload("res://data/bridge/support.tres")

## Rock ceiling at row 0, rock wall in column 0, open air in between.
const CRANE: Array = [
	"RRRRRRRR",
	"R.......",
	"R.......",
	"R.......",
	"R.......",
	"R.......",
	"R.......",
	"BBBBBBBB",
]

const CHASM: Array = [
	"..........",
	"..........",
	"###....###",
	"###....###",
	"###....###",
	"BBBBBBBBBB",
]


func _run(b: Bridge, seconds: float, loads: Array = []) -> void:
	for i in int(seconds * 60):
		b.step(1.0 / 60.0, loads)


func test_anchorable_only_touching_ground() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	assert_true(b.anchorable(Vector2(3, 2)), "corner of ground")
	assert_false(b.anchorable(Vector2(5, 1)), "mid air")


## A support costs 1 log per started 2 m (its Metres Per Cost); a log 1 per started metre.
func test_supports_cost_a_log_per_started_two_metres() -> void:
	var support: BridgeMaterial = load("res://data/bridge/support.tres")
	assert_eq(support.metres_per_cost, 2.0)
	for pair in [[1.0, 1], [2.0, 1], [2.5, 2], [4.0, 2], [4.5, 3]]:
		assert_eq(Bridge.cost_for(support, pair[0]).logs, pair[1], "%s m of support" % pair[0])
	assert_eq(Bridge.cost_for(LOG, 2.5).logs, 3, "a log still per started metre")


func test_check_build_says_how_much_is_missing() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var check := b.check_build(b.snap_point(Vector2(2, 2)), b.snap_point(Vector2(5, 2)), LOG, Supplies.make(0, 1))
	assert_false(check.ok)
	assert_string_starts_with(check.msg, "3.0 m · 2 logs missing", "3 m of log, 1 log in hand")


## "Too long" only when a shorter piece could be built: with nothing to build even the shortest, it says what is missing.
func test_too_long_without_supplies_says_what_is_missing() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var a := b.snap_point(Vector2(1, 2))
	var far := b.snap_point(Vector2(8, 2))
	var broke := b.check_build(a, far, LOG, Supplies.new())
	assert_false(broke.ok)
	assert_string_starts_with(broke.msg, "7.0 m · 7 logs missing", "not even the shortest piece can be paid for")
	var some := b.check_build(a, far, LOG, Supplies.make(0, 2))
	assert_eq(some.msg, b.too_long_text % [some.length, LOG.max_length], "a shorter one can be built")


func test_check_build_rejects() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var plenty := Supplies.make(9, 9, 9, 9)
	assert_false(b.check_build(b.snap_point(Vector2(1, 2)), b.snap_point(Vector2(8, 2)), LOG, plenty).ok, "too long")
	assert_true(b.check_build(b.snap_point(Vector2(5, 0)), b.snap_point(Vector2(6, 0)), LOG, plenty).ok, "may start in mid-air")
	assert_false(b.check_build(b.snap_point(Vector2(1, 2)), b.snap_point(Vector2(1, 5)), LOG, plenty).ok, "through ground")
	assert_false(b.check_build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, Supplies.new()).ok, "no logs")
	assert_true(b.check_build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, plenty).ok)


func test_snap_to_half_metre_and_existing_joint() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var p := b.snap_point(Vector2(4.3, 1.1))
	assert_eq(p.pos, Vector2(4.5, 1.0))
	b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 1)), LOG)
	assert_not_null(b.snap_point(Vector2(5.2, 1.1)).node, "snaps to the joint")


func test_log_across_chasm_holds() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	_run(b, 2.0)
	assert_eq(b.members.size(), 1)
	assert_almost_eq(m.b.pos.y, 2.0, 0.05)


func test_hinged_log_swings_down() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(6, 2)), LOG)
	_run(b, 0.5)
	assert_gt(m.b.pos.y, 2.5, "free end falls")


func test_rope_crane_holds_soldier() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	var arm := b.build(b.snap_point(Vector2(1, 5)), b.snap_point(Vector2(5, 5)), LOG)
	b.build(b.snap_point(Vector2(5, 1)), b.snap_point(Vector2(5, 5)), ROPE)
	_run(b, 2.0, [[arm, 1.0, 80.0]])
	assert_eq(b.members.size(), 2)


func test_rope_crane_snaps_when_overloaded() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	var arm := b.build(b.snap_point(Vector2(1, 5)), b.snap_point(Vector2(5, 5)), LOG)
	var rope := b.build(b.snap_point(Vector2(5, 1)), b.snap_point(Vector2(5, 5)), ROPE)
	watch_signals(b)
	_run(b, 2.0, [[arm, 1.0, 2000.0]])
	assert_false(rope in b.members, "rope broke")
	assert_signal_emitted(b, "member_broken")


func test_rope_never_pushes() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(6, 2)), ROPE)
	_run(b, 1.0)
	assert_lt(m.b.pos.distance_to(m.a.pos), m.length + 0.01)
	assert_gt(m.b.pos.y, 2.5, "rope end hangs")


func test_walk_surface_on_log() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var s: Dictionary = b.walk_surface(5.0, 0.0)
	assert_eq(s.member, m)
	assert_almost_eq(s.y, 2.0 - b.deck_offset, 0.01)


func test_remove_member_drops_orphan_nodes() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	b.remove_member(m)
	assert_eq(b.members.size(), 0)
	assert_eq(b.nodes.size(), 0)


func test_blueprint_is_not_simulated() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(6, 2)), LOG, true)
	_run(b, 0.5)
	assert_true(m.blueprint)
	assert_almost_eq(m.b.pos.y, 2.0, 0.001, "plan does not fall")


func test_blueprint_is_not_walkable() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	assert_true(b.walk_surface(5.0, 0.0).is_empty())


func test_blueprint_adds_no_weight_to_built_joint() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var deck := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG)
	var built_mass := deck.b.mass
	b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 0)), LOG, true)
	assert_almost_eq(deck.b.mass, built_mass, 0.001)


func test_order_does_not_build_yet() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	assert_eq(b.blueprint_count(), 1)
	assert_eq(b.order_blueprints(), 1)
	assert_true(m.blueprint, "waits for the crew")
	assert_true(m.ordered)
	assert_eq(b.blueprint_count(), 0, "no unordered plans left")


func test_finished_member_stays_on_scaffolding_until_struck() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(6, 2)), LOG, true)
	b.order_blueprints()
	b.finish(m)
	assert_false(m.blueprint)
	assert_true(m.scaffolded)
	assert_eq(b.walk_surface(4.5, 0.0).member, m, "finished parts can be walked on while still scaffolded")
	_run(b, 0.5)
	assert_almost_eq(m.b.pos.y, 2.0, 0.001, "scaffolding holds it")
	assert_eq(b.strike_scaffolding(), 1)
	assert_eq(b.walk_surface(4.5, 0.0).member, m)
	_run(b, 0.5)
	assert_gt(m.b.pos.y, 2.5, "hinge swings once struck")


func test_crossing_plan_holds_after_strike() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	b.order_blueprints()
	b.finish(m)
	b.strike_scaffolding()
	_run(b, 2.0)
	assert_almost_eq(m.b.pos.y, 2.0, 0.05)


func test_work_starts_from_ground_or_finished_structure() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m1 := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG, true)
	var m2 := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 0)), LOG, true)
	b.order_blueprints()
	assert_eq(b.work_ends(m1), [m1.a] as Array[Bridge.Joint], "bolted end")
	assert_eq(b.work_ends(m2), [] as Array[Bridge.Joint], "nothing to stand on yet")
	b.finish(m1)
	assert_eq(b.work_ends(m2), [m1.b] as Array[Bridge.Joint])
	assert_eq(b.route_from_ground(m1.b), [m1.a, m1.b] as Array[Bridge.Joint])


func test_support_holds_but_is_not_walkable() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), SUPPORT)
	assert_true(b.walk_surface(5.0, 0.0).is_empty())
	_run(b, 2.0)
	assert_true(m in b.members)
	assert_almost_eq(m.b.pos.y, 2.0, 0.05)


func test_remove_outside_drops_members_with_an_end_beyond() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var left := b.build(b.snap_point(Vector2(1, 2)), b.snap_point(Vector2(3, 2)), LOG)
	var across := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	b.remove_outside(0.0, 5.0)
	assert_true(left in b.members)
	assert_false(across in b.members, "blueprints go too")
	assert_true(across.dead)
	b.remove_outside(2.0, 100.0)
	assert_eq(b.members.size(), 0)
	assert_eq(b.nodes.size(), 0)


func test_structures_are_separate_unless_connected() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m1 := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG)
	var m2 := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	var m3 := b.build(b.snap_point(Vector2(8, 2)), b.snap_point(Vector2(8, 0)), LOG)
	b.order_blueprints()
	var plan := b.build(b.snap_point(Vector2(7, 2)), b.snap_point(Vector2(8, 0)), ROPE, true)
	assert_eq(b.structures().size(), 2, "an unordered plan does not join them")
	assert_true(m1 in b.structure_of(m2))
	assert_false(m3 in b.structure_of(m1))
	assert_false(plan in b.structure_of(m1))
	b.order_blueprints()
	assert_eq(b.structures().size(), 1, "an ordered member joins them")


func test_logs_block_arrow_paths_ropes_and_plans_do_not() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	var post := b.build(b.snap_point(Vector2(4, 1)), b.snap_point(Vector2(4, 4)), LOG)
	var hit: Variant = b.arrow_block(Vector2(2, 2.5), Vector2(6, 2.5))
	assert_true(hit is Vector2, "a log stops the arrow")
	assert_almost_eq((hit as Vector2).x, 4.0, 0.01)
	assert_null(b.arrow_block(Vector2(2, 5.5), Vector2(6, 5.5)), "passes under the log")
	b.remove_member(post)
	b.build(b.snap_point(Vector2(4, 1)), b.snap_point(Vector2(4, 4)), ROPE)
	assert_null(b.arrow_block(Vector2(2, 2.5), Vector2(6, 2.5)), "ropes do not block")
	b.build(b.snap_point(Vector2(5, 1)), b.snap_point(Vector2(5, 4)), LOG, true)
	assert_null(b.arrow_block(Vector2(2, 2.5), Vector2(6, 2.5)), "plans do not block")


func test_plans_group_unordered_blueprints_by_shared_joints() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var left := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG, true)
	var joined := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 0)), SUPPORT, true)
	var apart := b.build(b.snap_point(Vector2(7, 2)), b.snap_point(Vector2(9, 2)), LOG, true)
	b.build(b.snap_point(Vector2(0, 2)), b.snap_point(Vector2(2, 2)), LOG)
	var plans := b.plans()
	assert_eq(plans.size(), 2, "the built log is not a plan")
	assert_true(plans.any(func(p: Array) -> bool: return left in p and joined in p and not apart in p))
	b.order_plan(plans.filter(func(p: Array) -> bool: return apart in p)[0])
	assert_true(apart.ordered)
	assert_false(left.ordered, "only that plan is ordered")
	assert_eq(b.plans().size(), 1)


func test_cancel_plan_removes_it_and_returns_its_cost() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var kept := b.build(b.snap_point(Vector2(0, 2)), b.snap_point(Vector2(2, 2)), LOG, true)
	b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG, true)
	b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 0)), ROPE, true)
	var plan: Array = b.plans().filter(func(p: Array) -> bool: return not kept in p)[0]
	var refund := b.cancel_plan(plan)
	assert_eq([refund.logs, refund.rope], [2, 2], "a 2 m log and a 2 m rope, per started metre")
	assert_eq(b.members, [kept] as Array[Bridge.Member])


func test_snaps_along_a_bridge_not_only_to_its_ends() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var deck := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var s := b.snap_point(Vector2(5.2, 2.1))
	assert_eq(s.on_member, deck)
	assert_almost_eq(s.pos, Vector2(5.2, 2.0), Vector2(0.01, 0.01), "on the log")
	assert_null(s.node)


func test_ropes_are_only_joined_at_their_ends() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	b.build(b.snap_point(Vector2(5, 1)), b.snap_point(Vector2(5, 5)), ROPE)
	assert_null(b.snap_point(Vector2(5.1, 3)).on_member)


func test_building_from_the_middle_splits_the_bridge() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var deck := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var support := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 5)), SUPPORT)
	assert_eq(b.members.size(), 3, "deck split in two, plus the support")
	var mid := support.a
	assert_eq(deck.b, mid, "the deck now ends at the new joint")
	var other: Bridge.Member = b.members.filter(func(m: Bridge.Member) -> bool: return m != deck and m != support)[0]
	assert_eq(other.a, mid)
	assert_almost_eq(deck.length + other.length, 4.0, 0.001)
	assert_eq(other.material, deck.material)


func test_split_bridge_on_a_support_holds() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var support := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(5, 5)), SUPPORT)
	_run(b, 2.0, [[support, 0.0, 160.0]])
	assert_eq(b.members.size(), 3)
	assert_almost_eq(support.a.pos.y, 2.0, 0.05, "the middle stays up")


func test_can_not_join_a_bridge_to_its_own_end() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var deck := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var plenty := Supplies.make(9, 9, 9, 9)
	assert_false(b.check_build(b.snap_point(Vector2(5, 2)), b.snap_point(deck.b.pos), LOG, plenty).ok)


func test_only_finished_parts_of_a_plan_are_walkable() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var first := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(5, 2)), LOG, true)
	var second := b.build(b.snap_point(Vector2(5, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	b.order_blueprints()
	b.finish(first)
	second.progress = 0.5
	assert_eq(b.walk_surface(4.0, 0.0).member, first)
	assert_true(b.walk_surface(6.0, 0.0).is_empty(), "the piece being built is not")


const FLAT: Array = [
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"##########",
	"BBBBBBBBBB",
]


## Drops a loose structure (no bolted joints) built from plans, then lets it settle for seconds.
func _drop_loose(b: Bridge, plans: Array, seconds: float) -> void:
	for p: Array in plans:
		b.build(b.snap_point(p[0]), b.snap_point(p[1]), p[2], true)
	b.order_blueprints()
	for m in b.members.duplicate():
		b.finish(m)
	b.strike_scaffolding()
	_run(b, seconds)


func test_loose_log_comes_to_rest_on_the_ground() -> void:
	var t := WorldFixture.terrain(self, FLAT)
	var b := WorldFixture.bridge(self, t)
	_drop_loose(b, [[Vector2(2, 3), Vector2(5, 3), LOG]], 2.0)
	var worst := 0.0
	for i in 60:
		_run(b, 1.0 / 60.0)
		for n in b.nodes:
			worst = maxf(worst, absf(n.pos.y - 6.0))
	assert_lt(worst, 0.03, "lies still on the ground, no hopping")


func test_loose_frame_settles_with_steady_forces() -> void:
	var t := WorldFixture.terrain(self, FLAT)
	var b := WorldFixture.bridge(self, t)
	_drop_loose(b, [[Vector2(2, 3), Vector2(5, 3), LOG], [Vector2(2, 3), Vector2(3.5, 1), SUPPORT], [Vector2(3.5, 1), Vector2(5, 3), SUPPORT]], 3.0)
	var lo := {}
	var hi := {}
	for i in 60:
		_run(b, 1.0 / 60.0)
		for m in b.members:
			lo[m] = minf(lo.get(m, INF), m.force)
			hi[m] = maxf(hi.get(m, -INF), m.force)
	for m: Bridge.Member in b.members:
		assert_lt(hi[m] - lo[m], 20.0, "%s force holds steady at rest" % m.material.display_name)


func test_supports_let_arrows_through() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	b.build(b.snap_point(Vector2(4, 1)), b.snap_point(Vector2(4, 4)), SUPPORT)
	assert_null(b.arrow_block(Vector2(2, 2.5), Vector2(6, 2.5)), "arrows fly past supports")


func test_the_built_part_of_a_piece_in_progress_is_walkable() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG, true)
	b.order_blueprints()
	m.from_joint = m.a
	m.progress = 0.5
	var on := b.walk_surface(4.0, 0.0)
	assert_eq(on.get("member"), m, "built half carries you")
	assert_true(b.walk_surface(6.0, 0.0).is_empty(), "the rest is not built yet")
	m.from_joint = m.b
	assert_true(b.walk_surface(4.0, 0.0).is_empty(), "building from the other end")
	assert_eq(b.walk_surface(6.0, 0.0).get("member"), m)


func test_plan_end_inside_the_ground_moves_to_where_the_plan_leaves_it() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var to := b.snap_point(Vector2(5, 1))
	var from := b.fit_to_ground(b.snap_point(Vector2(2, 3)), to)
	assert_almost_eq(from.pos, Vector2(3, 3.0 - 2.0 / 3.0), Vector2(0.01, 0.01), "on the ground's face")
	assert_true(from.anchor, "bolted there")
	assert_true(b.check_build(from, to, LOG, Supplies.make(9, 9, 9, 9)).ok)
	var air := b.snap_point(Vector2(6, 1))
	assert_eq(b.fit_to_ground(air, to), air, "an end in the air stays")


func test_joints_bolt_to_any_solid_tile() -> void:
	var t := WorldFixture.terrain(self, [
		"..........",
		"..........",
		"..........",
		".KK....RR.",
		".KK....RR.",
		".KK....RR.",
		"##########",
		"BBBBBBBBBB",
	])
	var b := WorldFixture.bridge(self, t)
	assert_true(b.anchorable(Vector2(3, 3)), "a tower's corner")
	assert_true(b.anchorable(Vector2(3, 4.5)), "a tower's wall")
	assert_true(b.anchorable(Vector2(7, 4)), "rock")
	assert_true(b.anchorable(Vector2(5, 6)), "the ground")
	assert_false(b.anchorable(Vector2(5, 2)), "not mid-air")


## A loose 4 m log dropped onto the ledge (top at row 4, ground up to x = 4) with on_ledge metres of it over the ledge.
func _log_over_ledge(on_ledge: float) -> Bridge.Member:
	var t := WorldFixture.terrain(self, [
		"............",
		"............",
		"............",
		"............",
		"####........",
		"####........",
		"####........",
		"####........",
		"############",
		"BBBBBBBBBBBB",
	])
	var b := WorldFixture.bridge(self, t)
	var x0 := 4.0 - on_ledge
	# Let go half a metre above the ledge, so it rests there instead of being bolted.
	var m := b.build(b.snap_point(Vector2(x0, 3.5)), b.snap_point(Vector2(x0 + 4.0, 3.5)), LOG)
	assert_false(m.a.pinned or m.b.pinned, "loose")
	_run(b, 4.0)
	return m


func test_a_log_mostly_off_a_ledge_tips_off_it() -> void:
	var m := _log_over_ledge(0.5)
	assert_gt(m.b.pos.y, 6.0, "the overhanging end went down")
	assert_gt(m.a.pos.x, 4.0, "and it slid off the ledge")


func test_a_log_mostly_on_a_ledge_stays() -> void:
	var m := _log_over_ledge(3.0)
	assert_lt(m.a.pos.y, 4.1, "still lying on the ledge")
	assert_lt(m.b.pos.y, 4.1)


func test_loaded_plank_sags_and_soldiers_stand_on_the_bend() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var m := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var flat: float = b.walk_surface(5.0, 0.0).y
	_run(b, 2.0, [[m, 0.5, 80.0]])
	assert_gt(m.sag, 0.02, "the middle sinks under a soldier")
	assert_almost_eq(b.walk_surface(5.0, 0.0).y, flat + m.sag, 0.01, "walking surface follows the bend")
	_run(b, 3.0)
	assert_lt(m.sag, 0.005, "springs back when the soldier leaves")


func test_long_planks_flex_much_more_than_short_ones() -> void:
	var t := WorldFixture.terrain(self, CHASM)
	var b := WorldFixture.bridge(self, t)
	var long := b.build(b.snap_point(Vector2(3, 2)), b.snap_point(Vector2(7, 2)), LOG)
	var short := b.build(b.snap_point(Vector2(1, 2)), b.snap_point(Vector2(2, 2)), LOG)
	_run(b, 2.0, [[long, 0.5, 80.0], [short, 0.5, 80.0]])
	assert_gt(long.sag, short.sag * 20.0, "sag grows with length cubed")


func test_ropes_do_not_flex() -> void:
	var t := WorldFixture.terrain(self, CRANE)
	var b := WorldFixture.bridge(self, t)
	var rope := b.build(b.snap_point(Vector2(1, 3)), b.snap_point(Vector2(5, 3)), ROPE)
	_run(b, 1.0, [[rope, 0.5, 80.0]])
	assert_eq(rope.sag, 0.0)


func test_a_plan_dragged_through_both_cliffs_fits_a_gap_its_own_length() -> void:
	var t := WorldFixture.terrain(self, [
		"............",
		"............",
		"###.....####",
		"###.....####",
		"BBBBBBBBBBBB",
	])
	var b := WorldFixture.bridge(self, t)
	# Dragged from inside the left cliff to inside the right one, across a 5 m gap (faces at x 3 and 8).
	var from := b.snap_point(Vector2(1.5, 2.5))
	var to := b.snap_point(Vector2(9.5, 2.5))
	var a := b.fit_to_ground(from, to)
	var z := b.fit_to_ground(to, a)
	assert_eq(a.pos, Vector2(3, 2.5), "on the left face")
	assert_eq(z.pos, Vector2(8, 2.5), "on the right face")
	assert_true(b.check_build(a, z, LOG, Supplies.make(9, 9, 9, 9)).ok, "a 5 m log fits a 5 m gap")
