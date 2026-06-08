class_name CharacterCreation
extends Control
## Minimal character-creation screen (ADR-0015/0016): pick 2 distinct classes and
## a race for each, then start the fight with those selections applied. Feeds the
## chosen party + races into BattleView (race stat mods apply to each character).
##
## Code-driven and asset-free, matching battle_view. A run-level flow (map, etc.)
## comes later; for now "Begin" launches a single encounter with your party.

const CLASSES: Array = [
	[&"fighter", "Fighter", "STR · bruiser"],
	[&"rogue", "Rogue", "DEX · finesse"],
	[&"mage", "Mage", "INT · caster"],
]
const RACES: Array = [
	[&"human", "Human", "+1 all"],
	[&"elf", "Elf", "+DEX +INT"],
	[&"orc", "Orc", "+STR +CON"],
]

const COL_BG := Color(0.12, 0.13, 0.17)
const COL_SLOT := Color(0.16, 0.17, 0.22)
const COL_ACCENT := Color(0.40, 0.70, 0.95)
const COL_SEL := Color(0.26, 0.40, 0.30)
const COL_OFF := Color(0.20, 0.22, 0.28)

# Per-slot selections.
var _class: Array[StringName] = [&"", &""]
var _race: Array[StringName] = [&"", &""]

# Button registries for highlight updates: _class_btns[slot][class_id] = Button.
var _class_btns: Array[Dictionary] = [{}, {}]
var _race_btns: Array[Dictionary] = [{}, {}]
var _begin: Button
var _hint: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 14)
	root.offset_left = 24
	root.offset_top = 18
	root.offset_right = -24
	root.offset_bottom = -18
	add_child(root)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 22)
	title.text = "Create Your Party"
	root.add_child(title)

	var sub := Label.new()
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	sub.text = "Pick 2 (distinct) classes and a race for each."
	root.add_child(sub)

	for i in 2:
		root.add_child(_build_slot(i))

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	root.add_child(controls)
	_begin = Button.new()
	_begin.text = "Begin Battle"
	_begin.custom_minimum_size = Vector2(150, 40)
	_begin.pressed.connect(_on_begin)
	controls.add_child(_begin)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.85, 0.6, 0.5))
	controls.add_child(_hint)

	_refresh()


func _build_slot(slot: int) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_SLOT
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := Label.new()
	head.add_theme_color_override("font_color", COL_ACCENT)
	head.text = "PARTY SLOT %d" % (slot + 1)
	box.add_child(head)

	box.add_child(_chooser_row(slot, "Class", CLASSES, true))
	box.add_child(_chooser_row(slot, "Race", RACES, false))
	return panel


func _chooser_row(slot: int, label: String, options: Array, is_class: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(56, 0)
	lab.text = label
	row.add_child(lab)
	for opt in options:
		var id: StringName = opt[0]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 44)
		btn.text = "%s\n%s" % [opt[1], opt[2]]
		btn.pressed.connect(_on_choose.bind(slot, id, is_class))
		row.add_child(btn)
		if is_class:
			_class_btns[slot][id] = btn
		else:
			_race_btns[slot][id] = btn
	return row


func _on_choose(slot: int, id: StringName, is_class: bool) -> void:
	if is_class:
		_class[slot] = id
	else:
		_race[slot] = id
	_refresh()


func _refresh() -> void:
	for slot in 2:
		for id in _class_btns[slot]:
			_style(_class_btns[slot][id], _class[slot] == id)
		for id in _race_btns[slot]:
			_style(_race_btns[slot][id], _race[slot] == id)

	var both_classes := _class[0] != &"" and _class[1] != &""
	var both_races := _race[0] != &"" and _race[1] != &""
	var distinct := _class[0] != _class[1]
	_begin.disabled = not (both_classes and both_races and distinct)
	if both_classes and not distinct:
		_hint.text = "Pick two different classes."
	elif not (both_classes and both_races):
		_hint.text = "Choose a class and race for both slots."
	else:
		_hint.text = ""


func _style(btn: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_SEL if selected else COL_OFF
	sb.set_corner_radius_all(6)
	if selected:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(2)
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, sb)


func _on_begin() -> void:
	var view := BattleView.new()
	view.party = [_class[0], _class[1]] as Array[StringName]
	view.party_races = {_class[0]: _race[0], _class[1]: _race[1]}
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(view)
	queue_free()
