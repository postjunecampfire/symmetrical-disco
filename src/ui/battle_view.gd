class_name BattleView
extends Control
## Minimal positionless combat UI (P3, ADR-0013). A code-driven, asset-free
## battle screen so the engine can actually be PLAYED, not just tested:
##   - left column: your party (HP / block / statuses), click to select the actor;
##   - right column: enemies (HP / block / statuses / telegraphed intent), click
##     to target;
##   - bottom: the shared hand (click a card), the selected actor's innate
##     Strike/Defend, the shared energy pool, and End Turn.
##
## Flow: click a card or innate to ARM it. self / all_* effects resolve at once;
## enemy / ally effects wait for you to click a target. End Turn discards the
## hand and runs the enemy phase, then redraws and re-telegraphs. TPK / all-foes-
## dead shows a banner. This is a scoped exception to the UI hold so the loop is
## feelable before P3·09; the bigger run/map UI stays later.

const DATA_DIR := "res://data"
const ENCOUNTER_ID: StringName = &"skirmish_01"
const PARTY: Array[StringName] = [&"fighter", &"mage"]

const COL_BG := Color(0.12, 0.13, 0.17)
const COL_PANEL := Color(0.18, 0.20, 0.26)
const COL_PANEL_SEL := Color(0.26, 0.34, 0.46)
const COL_ENEMY := Color(0.30, 0.20, 0.22)
const COL_CARD := Color(0.20, 0.24, 0.30)
const COL_CARD_DIM := Color(0.15, 0.16, 0.19)
const COL_ACCENT := Color(0.40, 0.70, 0.95)

var _db: ContentDatabase
var _battle: EncounterBattle
var _card_play: CardPlay

var _selected_actor: Combatant = null
var _armed_card: CardData = null
var _armed_innate: CardData = null
var _armed_actor: Combatant = null
var _await_target: StringName = &""   # "enemy" | "ally" | "" (none)

var _status_text: String = "Your turn."
var _finished: bool = false

# Built-once containers; repopulated each refresh.
var _party_box: VBoxContainer
var _enemy_box: VBoxContainer
var _hand_box: HBoxContainer
var _innate_box: HBoxContainer
var _header: Label
var _banner: Label


func _ready() -> void:
	_load_and_assemble()
	_build_layout()
	if _battle != null:
		_begin_player_turn()
	_refresh()


# --- Setup ------------------------------------------------------------------

func _load_and_assemble() -> void:
	_db = ContentDatabase.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	if not result.ok:
		_status_text = "Content failed to load: %s" % str(result.errors)
		return
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	if encounter == null:
		_status_text = "Encounter '%s' not found." % ENCOUNTER_ID
		return
	_battle = EncounterAssembler.new().build(encounter, _db, PARTY, randi())
	_card_play = CardPlay.new(_battle)
	_selected_actor = _battle.living_players()[0] if not _battle.living_players().is_empty() else null


func _begin_player_turn() -> void:
	_battle.start_player_turn()
	# Telegraph each enemy's next action for display.
	if _battle.enemy_ai != null:
		for enemy in _battle.living_enemies():
			var data: EnemyData = enemy.source_data as EnemyData
			if data != null:
				_battle.enemy_ai.select_intent(enemy, data, _battle)
	_clear_armed()
	_status_text = "Your turn — energy %d." % _battle.energy


# --- Static layout ----------------------------------------------------------

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 18)
	root.add_child(_header)

	# Middle: party | enemies
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 24)
	root.add_child(mid)

	_party_box = _titled_column(mid, "PARTY")
	_enemy_box = _titled_column(mid, "ENEMIES")

	# Bottom: innate bar + hand + end turn
	var innate_row := HBoxContainer.new()
	innate_row.add_theme_constant_override("separation", 8)
	root.add_child(innate_row)
	var innate_label := Label.new()
	innate_label.text = "Innate:"
	innate_row.add_child(innate_label)
	_innate_box = HBoxContainer.new()
	_innate_box.add_theme_constant_override("separation", 8)
	innate_row.add_child(_innate_box)

	var hand_label := Label.new()
	hand_label.text = "Hand:"
	root.add_child(hand_label)
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 8)
	_hand_box.custom_minimum_size = Vector2(0, 110)
	root.add_child(_hand_box)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	root.add_child(controls)
	var end_btn := Button.new()
	end_btn.text = "End Turn"
	end_btn.custom_minimum_size = Vector2(120, 36)
	end_btn.pressed.connect(_on_end_turn)
	controls.add_child(end_btn)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.add_theme_color_override("font_color", COL_ACCENT)
	controls.add_child(_banner)


func _titled_column(parent: Control, title: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 8)
	parent.add_child(wrap)
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", COL_ACCENT)
	wrap.add_child(t)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	wrap.add_child(box)
	return box


# --- Refresh (rebuild dynamic parts) ----------------------------------------

func _refresh() -> void:
	if _battle == null:
		_header.text = _status_text
		return
	_header.text = "Turn %d   |   Energy %d   |   %s" % [
		_battle.turn_number, _battle.energy, _status_text
	]
	_rebuild_party()
	_rebuild_enemies()
	_rebuild_innate()
	_rebuild_hand()


func _rebuild_party() -> void:
	_clear(_party_box)
	for unit in _battle.living_players():
		var selectable := not _finished
		var btn := _unit_panel(unit, false, unit == _selected_actor)
		if selectable:
			btn.pressed.connect(_on_party_clicked.bind(unit))
		_party_box.add_child(btn)


func _rebuild_enemies() -> void:
	_clear(_enemy_box)
	for unit in _battle.living_enemies():
		var btn := _unit_panel(unit, true, false)
		if not _finished:
			btn.pressed.connect(_on_enemy_clicked.bind(unit))
		_enemy_box.add_child(btn)


func _unit_panel(unit: Combatant, is_enemy: bool, selected: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 64)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", Color.WHITE)
	var col := COL_ENEMY if is_enemy else COL_PANEL
	if selected:
		col = COL_PANEL_SEL
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	var parts: Array[String] = []
	parts.append("%s   HP %d/%d" % [unit.display_name, unit.hp, unit.max_hp])
	var second: Array[String] = []
	if unit.block > 0:
		second.append("BLK %d" % unit.block)
	var st := _status_summary(unit)
	if st != "":
		second.append(st)
	if is_enemy:
		var intent := _intent_summary(unit)
		if intent != "":
			second.append("Intent: " + intent)
	if not second.is_empty():
		parts.append("   ".join(second))
	btn.text = "\n".join(parts)
	return btn


func _rebuild_innate() -> void:
	_clear(_innate_box)
	if _selected_actor == null or _finished:
		return
	var data := _selected_actor.source_data as CharacterData
	if data == null:
		return
	for innate_id in data.innate_actions:
		var card: CardData = _db.get_card(innate_id)
		if card == null:
			continue
		var btn := Button.new()
		btn.text = "%s (%d)" % [card.display_name, card.energy_cost]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.disabled = card.energy_cost > _battle.energy
		btn.pressed.connect(_on_innate_pressed.bind(card, _selected_actor))
		_innate_box.add_child(btn)


func _rebuild_hand() -> void:
	_clear(_hand_box)
	for card in _battle.deck.hand:
		_hand_box.add_child(_card_button(card))


func _card_button(card: CardData) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 100)
	btn.clip_text = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	var actor := _actor_for_card(card)
	var playable := actor != null and card.energy_cost <= _battle.energy and not _finished
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD if playable else COL_CARD_DIM
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	if _armed_card == card:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_font_size_override("font_size", 12)
	var owner_txt := "neutral" if card.character_tag == &"neutral" else String(card.character_tag)
	btn.text = "%s  (%d)\n[%s]\n%s" % [
		card.display_name, card.energy_cost, owner_txt, _card_effects_summary(card)
	]
	btn.disabled = not playable
	btn.pressed.connect(_on_card_pressed.bind(card))
	return btn


# --- Interaction ------------------------------------------------------------

func _on_party_clicked(unit: Combatant) -> void:
	if _await_target == &"ally":
		_resolve_play(_armed_actor, _armed_card, _armed_innate, unit)
		return
	_selected_actor = unit
	_status_text = "%s selected." % unit.display_name
	_refresh()


func _on_enemy_clicked(unit: Combatant) -> void:
	if _await_target == &"enemy":
		_resolve_play(_armed_actor, _armed_card, _armed_innate, unit)
	else:
		_status_text = "Arm a card or Strike, then click an enemy."
		_refresh()


func _on_card_pressed(card: CardData) -> void:
	var actor := _actor_for_card(card)
	if actor == null:
		_status_text = "No one can play %s right now." % card.display_name
		_refresh()
		return
	if card.energy_cost > _battle.energy:
		_status_text = "Not enough energy for %s." % card.display_name
		_refresh()
		return
	_arm(card, null, actor)


func _on_innate_pressed(card: CardData, actor: Combatant) -> void:
	_arm(null, card, actor)


func _arm(card: CardData, innate: CardData, actor: Combatant) -> void:
	_armed_card = card
	_armed_innate = innate
	_armed_actor = actor
	var spec: TargetSpec = (card if card != null else innate).target
	var kind: StringName = spec.target_type if spec != null else &"enemy"
	match kind:
		&"self", &"all_allies", &"all_enemies", &"random_enemy":
			_resolve_play(actor, card, innate, null if kind != &"self" else actor)
		&"enemy":
			_await_target = &"enemy"
			_status_text = "Click an enemy target."
			_refresh()
		&"ally":
			_await_target = &"ally"
			_status_text = "Click an ally target."
			_refresh()
		_:
			_clear_armed()
			_status_text = "Unknown target type '%s'." % kind
			_refresh()


func _resolve_play(actor: Combatant, card: CardData, innate: CardData, target: Variant) -> void:
	var result: CardPlay.PlayResult
	if innate != null:
		result = _card_play.play_innate(actor, innate, target)
	else:
		result = _card_play.play_card(actor, card, target)
	if result.ok:
		var name := (innate if innate != null else card).display_name
		_status_text = "%s played %s." % [actor.display_name, name]
	else:
		_status_text = result.reason
	_clear_armed()
	_check_outcome()
	_refresh()


func _on_end_turn() -> void:
	if _finished:
		return
	_clear_armed()
	_battle.end_player_turn()
	if _check_outcome():
		_refresh()
		return
	_begin_player_turn()
	_refresh()


# --- Helpers ----------------------------------------------------------------

## The combatant who would play `card`: a tagged card -> its owner; a neutral
## card -> the currently selected actor. Null if no eligible, living actor.
func _actor_for_card(card: CardData) -> Combatant:
	if card.character_tag == &"neutral":
		return _selected_actor
	for p in _battle.living_players():
		var data := p.source_data as CharacterData
		if data != null and data.id == card.character_tag:
			return p
	return null


func _clear_armed() -> void:
	_armed_card = null
	_armed_innate = null
	_armed_actor = null
	_await_target = &""


func _check_outcome() -> bool:
	var outcome := _battle.check_outcome()
	if outcome == BattleState.Outcome.WIN:
		_finished = true
		_banner.text = "VICTORY"
		_status_text = "All enemies defeated."
	elif outcome == BattleState.Outcome.LOSS:
		_finished = true
		_banner.text = "DEFEAT"
		_status_text = "Your party was wiped."
	return _finished


func _status_summary(unit: Combatant) -> String:
	var bits: Array[String] = []
	for key in [&"poison", &"strength", &"weak", &"stun"]:
		var n := unit.status_stacks(key)
		if n > 0:
			bits.append("%s %d" % [String(key).substr(0, 3).to_upper(), n])
	return "  ".join(bits)


func _intent_summary(enemy: Combatant) -> String:
	if _battle.enemy_ai == null:
		return ""
	var tel: EnemyAI.Telegraph = _battle.enemy_ai.get_telegraph(enemy)
	if tel == null or tel.intent == null:
		return ""
	var icon := String(tel.intent.telegraph)
	var amount := 0
	for e in tel.intent.effects:
		if e is Effect and (e.type == &"damage" or e.type == &"block"):
			amount = e.amount
			break
	return "%s %d" % [icon, amount] if amount > 0 else icon


func _card_effects_summary(card: CardData) -> String:
	var bits: Array[String] = []
	for e in card.effects:
		if not (e is Effect):
			continue
		match e.type:
			&"damage": bits.append("%d dmg" % e.amount)
			&"block": bits.append("%d blk" % e.amount)
			&"heal": bits.append("heal %d" % e.amount)
			&"apply_status": bits.append("%d %s" % [e.stacks, e.status])
			&"draw": bits.append("draw %d" % e.amount)
			&"gain_energy": bits.append("+%d NRG" % e.amount)
	var tt := card.target.target_type if card.target != null else &"enemy"
	var line := ", ".join(bits)
	if tt == &"all_enemies":
		line += " (all)"
	elif tt == &"self":
		line += " (self)"
	elif tt == &"ally":
		line += " (ally)"
	return line


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
		node.remove_child(child)
