extends GutTest


func test_add_and_spend() -> void:
	var s := Supplies.make(3, 2, 1, 0)
	s.add(Supplies.make(1, 1, 1, 1))
	assert_eq([s.earth, s.logs, s.rope, s.gold], [4, 3, 2, 1])
	assert_true(s.spend(Supplies.make(4)))
	assert_eq(s.earth, 0)


func test_spend_refuses_when_short_and_changes_nothing() -> void:
	var s := Supplies.make(0, 1)
	assert_false(s.spend(Supplies.make(1, 1)))
	assert_eq([s.earth, s.logs], [0, 1])


func test_describe() -> void:
	assert_eq(Supplies.make(0, 5, 3).describe(), "+5 logs · +3 rope")
	assert_eq(Supplies.new().describe(), "")


func test_copy_is_independent() -> void:
	var a := Supplies.make(1)
	var b := a.copy()
	b.earth = 9
	assert_eq(a.earth, 1)


func test_stone_is_a_supply() -> void:
	var s := Supplies.make(0, 0, 0, 0, 2)
	assert_eq(s.stone, 2)
	assert_eq(s.describe(), "+2 stone")
	assert_false(s.can_afford(Supplies.make(0, 0, 0, 0, 3)))


func test_reclaimed_gives_one_less_of_each_but_at_least_one() -> void:
	var r := Supplies.make(0, 3, 1, 0, 2).reclaimed()
	assert_eq([r.earth, r.logs, r.rope, r.gold, r.stone], [0, 2, 1, 0, 1])


func test_short_of_is_what_is_missing_for_a_cost() -> void:
	var have := Supplies.make(0, 2, 5)
	var missing := have.short_of(Supplies.make(1, 5, 3))
	assert_eq([missing.earth, missing.logs, missing.rope], [1, 3, 0])
	assert_eq(have.missing_text(Supplies.make(0, 5), "%s missing. Fell a tree"), "3 logs missing. Fell a tree")
	assert_eq(have.missing_text(Supplies.make(0, 3), "%s missing"), "1 log missing")
