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
