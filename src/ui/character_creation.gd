class_name CharacterCreation
extends Control
## Origin screen (ADR-0021 pt2 + ADR-0024): the run begins with ONE classless
## "normal person" — you pick a RACE only. The second member arrives via the
## Act-2 recruit offer; both choose a class together at the end of Act 3.
##
## Code-driven and asset-free, matching the other views.

const RACES: Array = [
	[&"human", "Human", "3/3/3/3 — balanced, flexible"],
	[&"elf", "Elf", "STR 2 · DEX 5 · CON 2 · INT 5 — fragile finesse"],
	[&"orc", "Orc", "STR 5 · DEX 3 · CON 4 · INT 2 — durable martial"],
]

const COL_BG := Color(0.10, 0.08, 0.07)
const COL_ACCENT := Color(0.72, 0.18, 0.16)
const COL_SEL := Color(0.26, 0.40, 0.30)
const COL_OFF := Color(0.20, 0.22, 0.28)

var _race: StringName = &""
var _race_btns: Dictionary = {}
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
	title.text = "Choose Your Origin"
	root.add_child(title)

	var sub := Label.new()
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	sub.text = "A lone, ordinary person enters the dungeon. Race is all you are — class comes later, if you survive to Act 3. A companion may join you in Act 2."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	root.add_child(row)
	for entry: Array in RACES:
		var rid: StringName = entry[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 190)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icon: Texture2D = UiAssets.character_sprite(rid)
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 84)
		b.text = "%s\n%s" % [entry[1], entry[2]]
		b.pressed.connect(_on_choose.bind(rid))
		_race_btns[rid] = b
		row.add_child(b)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(controls)
	_begin = Button.new()
	_begin.text = "Enter the Dungeon"
	_begin.custom_minimum_size = Vector2(180, 42)
	_begin.pressed.connect(_on_begin)
	controls.add_child(_begin)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.85, 0.6, 0.5))
	controls.add_child(_hint)

	# Offer to resume an in-progress run if one was saved (P2·02 save/resume).
	if FileAccess.file_exists(RunState.DEFAULT_SAVE_PATH):
		var cont := Button.new()
		cont.text = "Continue Run"
		cont.custom_minimum_size = Vector2(150, 40)
		cont.pressed.connect(_on_continue_run)
		controls.add_child(cont)

	_refresh()


## Resume the saved run: load the RunState and hand it to a MapView.
func _on_continue_run() -> void:
	var state: RunState = RunState.load_from()
	if state == null:
		return
	var view := MapView.new()
	view.resume_state = state
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(view)
	queue_free()


func _on_choose(rid: StringName) -> void:
	_race = rid
	_refresh()


func _refresh() -> void:
	for rid: Variant in _race_btns:
		_style(_race_btns[rid], rid == _race)
	_begin.disabled = _race == &""
	_hint.text = "" if _race != &"" else "Choose a race to begin."


func _style(btn: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_SEL if selected else COL_OFF
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	if selected:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(2)
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, sb)


func _on_begin() -> void:
	# Launch the full run (ADR-0024: SOLO Act 1; the recruit offer fires at Act 2).
	var view := MapView.new()
	view.party = [&"hero_1"] as Array[StringName]
	view.party_races = {&"hero_1": _race}
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(view)
	queue_free()
