class_name BattleView
extends Control
## Minimal positionless combat UI (P3, ADR-0013). A code-driven, asset-free
## battle screen so the engine can actually be PLAYED, not just tested:
##   - left column: your party (HP / block / statuses), click to select the actor;
##   - right column: enemies (HP / block / statuses / telegraphed intent), click
##     to target;
##   - bottom: the SELECTED actor's hand (ADR-0026: per-member derived decks;
##     click a party panel to switch hands), per-member energy (ADR-0025), End Turn.
##
## Flow: click a card or innate to ARM it. self / all_* effects resolve at once;
## enemy / ally effects wait for you to click a target. End Turn discards the
## hand and runs the enemy phase, then redraws and re-telegraphs. TPK / all-foes-
## dead shows a banner. This is a scoped exception to the UI hold so the loop is
## feelable before P3·09; the bigger run/map UI stays later.

const DATA_DIR := "res://data"
const ENCOUNTER_ID: StringName = &"skirmish_01"

## Emitted once when the fight ends (WIN/LOSS) and the player clicks Continue. The
## run layer (MapView) listens to carry HP/XP back via RunController.finish_combat.
signal combat_finished(outcome: int)

## Party + race selections. Set by the creation screen before the node enters the
## tree; the defaults let battle_view run standalone (e.g. straight from main.tscn).
var party: Array[StringName] = [&"fighter", &"mage"]
var party_races: Dictionary = {}

## Run-layer injection (P2·10): when set before _ready, BattleView drives THIS
## pre-assembled battle (built by RunController.begin_combat with carried HP, run
## deck, races and allocated stats) instead of self-assembling a one-off skirmish.
## `injected_db` is the run's loaded ContentDatabase. Standalone (both null) keeps
## the original behaviour so battle_view still runs straight from main.tscn.
var injected_battle: EncounterBattle = null
var injected_db: ContentDatabase = null

## Optional run telemetry (injected by MapView alongside the battle). When set,
## every successful card/innate play is logged as a `card_played` event. Null
## (standalone battle_view) = no logging.
var telemetry: TelemetryLogger = null

## Player turns started this fight; reported to RunController.finish_combat so
## combat_result telemetry carries a real turn count (was hardcoded 0 from the UI).
var _turns: int = 0

const COL_BG := Color(0.07, 0.05, 0.045)       # dungeon wall (darker, owner 2026-06-10)
const COL_FLOOR := Color(0.13, 0.115, 0.10)    # stone floor strip
const COL_PANEL := Color(0.18, 0.20, 0.26)
const COL_PANEL_SEL := Color(0.26, 0.34, 0.46)
const COL_ENEMY := Color(0.30, 0.20, 0.22)
const COL_CARD := Color(0.20, 0.24, 0.30)
const COL_CARD_DIM := Color(0.15, 0.16, 0.19)
const COL_ACCENT := Color(0.40, 0.70, 0.95)

var _db: ContentDatabase
var _battle: EncounterBattle

## Fire-and-forget sound effects (UiAssets-resolved; silent when assets absent).
var _sfx: SfxPlayer
var _card_play: CardPlay

var _selected_actor: Combatant = null
var _armed_card: CardData = null
var _armed_actor: Combatant = null
var _await_target: StringName = &""   # "enemy" | "ally" | "" (none)

var _status_text: String = "Your turn."
var _finished: bool = false

# Built-once containers; repopulated each refresh.
var _party_box: HBoxContainer
var _enemy_box: HBoxContainer
var _hand_box: HBoxContainer
var _header: Label
var _hand_label: Label
var _banner: Label
var _continue_btn: Button
var _outcome_value: int = BattleState.Outcome.ONGOING


func _ready() -> void:
	_sfx = SfxPlayer.new()
	add_child(_sfx)
	_load_and_assemble()
	_build_layout()
	if _battle != null:
		_sfx.play(&"card_shuffle")  # the battle deck was just assembled
		_begin_player_turn()
	_refresh()


# --- Setup ------------------------------------------------------------------

func _load_and_assemble() -> void:
	# Run-layer path (P2·10): drive the injected, pre-assembled battle.
	if injected_battle != null:
		_db = injected_db if injected_db != null else ContentDatabase.new()
		_battle = injected_battle
		_card_play = CardPlay.new(_battle)
		var players: Array[Combatant] = _battle.living_players()
		_selected_actor = players[0] if not players.is_empty() else null
		return

	_db = ContentDatabase.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	if not result.ok:
		_status_text = "Content failed to load: %s" % str(result.errors)
		return
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	if encounter == null:
		_status_text = "Encounter '%s' not found." % ENCOUNTER_ID
		return
	_battle = EncounterAssembler.new().build(encounter, _db, party, randi(), {}, party_races)
	_card_play = CardPlay.new(_battle)
	_selected_actor = _battle.living_players()[0] if not _battle.living_players().is_empty() else null


func _begin_player_turn() -> void:
	_turns += 1
	# Detect the ADR-0006 cooldown reshuffle: if the discard pile empties into the
	# draw pile during the turn-start draw, the cycle refreshed — sound it.
	var discard_before: int = _battle.deck.discard_pile.size()
	_battle.start_player_turn()
	if discard_before > 0 and _battle.deck.discard_pile.is_empty():
		_sfx.play(&"card_shuffle")
	else:
		_sfx.play(&"card_draw")
	# Telegraph each enemy's next action for display.
	if _battle.enemy_ai != null:
		for enemy in _battle.living_enemies():
			var data: EnemyData = enemy.source_data as EnemyData
			if data != null:
				_battle.enemy_ai.select_intent(enemy, data, _battle)
	_clear_armed()
	_status_text = "Your turn — energy %s." % _energy_summary()


# --- Static layout ----------------------------------------------------------

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Stone-floor strip under the combatants (cheap StS-style depth).
	var floor_rect := ColorRect.new()
	floor_rect.color = COL_FLOOR
	floor_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floor_rect.anchor_top = 0.42
	floor_rect.anchor_bottom = 0.68
	floor_rect.offset_top = 0
	floor_rect.offset_bottom = 0
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)

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

	# Owner spec (2026-06-10, rev 2): PROTAGONISTS LEFT, ANTAGONISTS RIGHT.
	_party_box = _titled_column(mid, "")
	_enemy_box = _titled_column(mid, "")

	# Bottom: the selected actor's hand (ADR-0026) + end turn.
	_hand_label = Label.new()
	_hand_label.text = "Hand:"
	root.add_child(_hand_label)
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 8)
	_hand_box.custom_minimum_size = Vector2(0, 168)
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

	# Shown only when the fight ends; hands control back to the run layer (P2·10).
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(120, 36)
	_continue_btn.visible = false
	_continue_btn.pressed.connect(_on_continue)
	controls.add_child(_continue_btn)


func _titled_column(parent: Control, _title: String) -> HBoxContainer:
	# A horizontal line of combatant figures (sprite + HP bar), StS-style.
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(wrap)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	wrap.add_child(box)
	return box


# --- Refresh (rebuild dynamic parts) ----------------------------------------

func _refresh() -> void:
	if _battle == null:
		_header.text = _status_text
		return
	_header.text = "Turn %d   |   Energy %s   |   %s" % [
		_battle.turn_number, _energy_summary(), _status_text
	]
	_rebuild_party()
	_rebuild_enemies()
	_rebuild_hand()


func _rebuild_party() -> void:
	_clear(_party_box)
	for unit in _battle.living_players():
		var fig := _unit_figure(unit, false, unit == _selected_actor)
		_party_box.add_child(fig)


func _rebuild_enemies() -> void:
	_clear(_enemy_box)
	for unit in _battle.living_enemies():
		var fig := _unit_figure(unit, true, false)
		_enemy_box.add_child(fig)


## A combatant rendered StS-style: sprite (clickable), HP bar UNDER the sprite,
## then a small caption (block / statuses / intent / incoming).
func _unit_figure(unit: Combatant, is_enemy: bool, selected: bool) -> VBoxContainer:
	var fig := VBoxContainer.new()
	fig.alignment = BoxContainer.ALIGNMENT_CENTER
	fig.add_theme_constant_override("separation", 4)

	var btn := _unit_panel(unit, is_enemy, selected)
	if not _finished:
		if is_enemy:
			btn.pressed.connect(_on_enemy_clicked.bind(unit))
		else:
			btn.pressed.connect(_on_party_clicked.bind(unit))
	fig.add_child(btn)

	# HP bar under the sprite (owner spec).
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 12)
	bar.max_value = float(maxi(1, unit.max_hp))
	bar.value = float(unit.hp)
	bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.06, 0.06)
	bar_bg.set_corner_radius_all(3)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.72, 0.15, 0.13)
	bar_fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	fig.add_child(bar)

	var hp_lab := Label.new()
	hp_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lab.add_theme_font_size_override("font_size", 12)
	hp_lab.text = "%d/%d" % [unit.hp, unit.max_hp]
	fig.add_child(hp_lab)

	var caption := Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	caption.text = _figure_caption(unit, is_enemy)
	fig.add_child(caption)
	return fig


## The small text under a figure: name, block, statuses, intent/incoming.
func _figure_caption(unit: Combatant, is_enemy: bool) -> String:
	var lines: Array[String] = [unit.display_name]
	var second: Array[String] = []
	if unit.block > 0:
		second.append("BLK %d" % unit.block)
	var st := _status_summary(unit)
	if st != "":
		second.append(st)
	if is_enemy:
		var special := _battle.upcoming_special(unit)
		if special == &"summon":
			second.append("Reinforce ▲")
		elif special == &"empower":
			second.append("Empower ▲")
		else:
			var intent := _intent_summary(unit)
			if intent != "":
				second.append(intent)
	else:
		var incoming := _incoming_damage(unit)
		if incoming > 0:
			second.append("◀ %d" % incoming)
		second.append("⚡ %d" % _battle.energy_of(unit))
	if not second.is_empty():
		lines.append("  ".join(second))
	return "\n".join(lines)


func _unit_panel(unit: Combatant, _is_enemy: bool, selected: bool) -> Button:
	# The sprite itself is the click target (target/select). DCSS art is 32px —
	# rendered at ~3x, pixel-crisp. Falls back to a named flat button.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(110, 100)
	var sprite: Texture2D = UiAssets.unit_sprite(unit)
	if sprite != null:
		btn.icon = sprite
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 96)
		btn.expand_icon = true
		btn.text = ""
	else:
		btn.text = unit.display_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_content_margin_all(2)
	if selected:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	return btn


func _rebuild_hand() -> void:
	_clear(_hand_box)
	if _selected_actor == null:
		return
	var deck: Deck = _battle.deck_of(_selected_actor)
	_hand_label.text = "Hand — %s  (draw %d · discard %d):" % [
		_selected_actor.display_name, deck.draw_pile.size(), deck.discard_pile.size()
	]
	for card in deck.hand:
		_hand_box.add_child(_card_button(card))


func _card_button(card: CardData) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(128, 162)
	btn.clip_text = false
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var actor := _actor_for_card(card)
	# ADR-0029: `unplayable` (curses) renders as a permanently dead card.
	var dead_card := card.keywords.has(&"unplayable")
	var playable := (
		actor != null and not dead_card
		and card.energy_cost <= _battle.energy_of(actor) and not _finished
	)
	# Card frame (P2·13 asset pass): a Kenney 9-slice frame tinted by playability;
	# the armed highlight keeps the flat bordered style (StyleBoxTexture has no
	# border). Missing frame asset -> the original flat stylebox.
	var frame: Texture2D = UiAssets.texture(UiAssets.UI_CARD_FRAME)
	if frame != null and _armed_card != card:
		var sbt := StyleBoxTexture.new()
		sbt.texture = frame
		sbt.texture_margin_left = 8.0
		sbt.texture_margin_top = 8.0
		sbt.texture_margin_right = 8.0
		sbt.texture_margin_bottom = 8.0
		sbt.content_margin_left = 8.0
		sbt.content_margin_top = 8.0
		sbt.content_margin_right = 8.0
		sbt.content_margin_bottom = 8.0
		sbt.modulate_color = COL_CARD if playable else COL_CARD_DIM
		btn.add_theme_stylebox_override("normal", sbt)
		btn.add_theme_stylebox_override("hover", sbt)
		btn.add_theme_stylebox_override("pressed", sbt)
		btn.add_theme_stylebox_override("disabled", sbt)
	else:
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
	# Card icon (game-icons.net, resolved by card id; null -> text-only).
	var icon: Texture2D = UiAssets.card_icon(card.id)
	if icon != null:
		btn.icon = icon
		btn.add_theme_constant_override("icon_max_width", 56)
	btn.add_theme_font_size_override("font_size", 12)
	var owner_txt := "neutral" if card.character_tag == &"neutral" else String(card.character_tag)
	# ADR-0029: an unplayable curse shows "—" for its cost (it has none).
	var cost_txt := "—" if dead_card else str(card.energy_cost)
	btn.text = "%s  (%s)\n[%s]\n%s" % [
		card.display_name, cost_txt, owner_txt, _card_effects_summary(card, actor)
	]
	btn.disabled = not playable
	btn.pressed.connect(_on_card_pressed.bind(card))
	return btn


# --- Interaction ------------------------------------------------------------

func _on_party_clicked(unit: Combatant) -> void:
	if _await_target == &"ally":
		_resolve_play(_armed_actor, _armed_card, unit)
		return
	_selected_actor = unit
	_status_text = "%s selected." % unit.display_name
	_refresh()


func _on_enemy_clicked(unit: Combatant) -> void:
	if _await_target == &"enemy":
		_resolve_play(_armed_actor, _armed_card, unit)
	else:
		_status_text = "Arm a card or Strike, then click an enemy."
		_refresh()


func _on_card_pressed(card: CardData) -> void:
	var actor := _actor_for_card(card)
	if actor == null:
		_status_text = "No one can play %s right now." % card.display_name
		_refresh()
		return
	if card.energy_cost > _battle.energy_of(actor):
		_status_text = "Not enough energy for %s (%s's pool)." % [card.display_name, actor.display_name]
		_refresh()
		return
	_arm(card, actor)


func _arm(card: CardData, actor: Combatant) -> void:
	_armed_card = card
	_armed_actor = actor
	var spec: TargetSpec = card.target
	var kind: StringName = spec.target_type if spec != null else &"enemy"
	match kind:
		&"self", &"all_allies", &"all_enemies", &"random_enemy":
			_resolve_play(actor, card, null if kind != &"self" else actor)
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


func _resolve_play(actor: Combatant, card: CardData, target: Variant) -> void:
	var result: CardPlay.PlayResult = _card_play.play_card(actor, card, target)
	if result.ok:
		var played: CardData = card
		_status_text = "%s played %s." % [actor.display_name, played.display_name]
		_play_card_sfx(played)
		if telemetry != null:
			var actor_data := actor.source_data as CharacterData
			telemetry.log_event(&"card_played", {
				"card": String(played.id),
				"actor": String(actor_data.id) if actor_data != null else actor.display_name,

				"turn": _turns,
				"energy_left": _battle.energy_of(actor),
			})
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

## Player turns started this fight (for run telemetry via finish_combat).
func turns_taken() -> int:
	return _turns


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
	_armed_actor = null
	_await_target = &""


func _check_outcome() -> bool:
	var outcome := _battle.check_outcome()
	if outcome == BattleState.Outcome.WIN:
		if not _finished:
			_sfx.play(&"victory")
		_finished = true
		_banner.text = "VICTORY"
		_status_text = "All enemies defeated."
	elif outcome == BattleState.Outcome.LOSS:
		if not _finished:
			_sfx.play(&"defeat")
		_finished = true
		_banner.text = "DEFEAT"
		_status_text = "Your party was wiped."
	if _finished:
		_outcome_value = outcome
		if _continue_btn != null:
			_continue_btn.visible = true
	return _finished


## Player acknowledged the result: hand control back to the run layer. In
## standalone mode (no listener) the button simply does nothing further.
func _on_continue() -> void:
	combat_finished.emit(_outcome_value)


## Card-play audio (P2·13): the cardstock sound always, plus a hit or a metal
## clink layered on top when the card deals damage / grants block. All cues are
## silent no-ops when audio assets are absent.
func _play_card_sfx(played: CardData) -> void:
	_sfx.play(&"card_play")
	for e in played.effects:
		if e is Effect and (e as Effect).type == &"damage":
			_sfx.play(&"hit")
			return
	for e in played.effects:
		if e is Effect and (e as Effect).type == &"block":
			_sfx.play(&"block")
			return


## Per-character pools (ADR-0025), e.g. "Fighter 2 · Mage 1".
func _energy_summary() -> String:
	var bits: PackedStringArray = PackedStringArray()
	for unit in _battle.living_players():
		bits.append("%s %d" % [unit.display_name, _battle.energy_of(unit)])
	return " · ".join(bits)


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
	var base: String = "%s %d" % [icon, amount] if amount > 0 else icon
	# Surface WHO the intent hits. _choose_target sets target to the enemy itself
	# for self/buff intents and to a player for offensive ones, so a target that
	# isn't the caster means an attack aimed at that ally (or "all" for AoE).
	if tel.target != null and tel.target != enemy:
		if _intent_target_kind(tel.intent) == &"all_enemies":
			base += " → all"
		else:
			base += " → %s" % tel.target.display_name
	return base


## The TargetSpec kind of an intent (from the ENEMY's perspective, where
## "all_enemies" means all players). Defaults to single-target "enemy".
func _intent_target_kind(intent: IntentData) -> StringName:
	if intent == null or intent.target == null:
		return &"enemy"
	return intent.target.target_type


## Total damage telegraphed at `ally` this turn, summed across living enemies.
## Single-target attacks count only against their chosen victim; AoE (all_enemies)
## counts against every ally. Ramp/summon turns (which replace the attack) and
## non-damage intents (block/buff/debuff) contribute nothing.
func _incoming_damage(ally: Combatant) -> int:
	if _battle.enemy_ai == null:
		return 0
	var total := 0
	for enemy in _battle.living_enemies():
		var special := _battle.upcoming_special(enemy)
		if special == &"summon" or special == &"empower":
			continue
		var tel: EnemyAI.Telegraph = _battle.enemy_ai.get_telegraph(enemy)
		if tel == null or tel.intent == null:
			continue
		var dmg := _intent_damage(tel.intent)
		if dmg <= 0:
			continue
		if _intent_target_kind(tel.intent) == &"all_enemies":
			total += dmg
		elif tel.target == ally:
			total += dmg
	return total


## Sum of an intent's raw damage-effect amounts (pre-Strength/Vulnerable, matching
## the telegraphed intent number).
func _intent_damage(intent: IntentData) -> int:
	var total := 0
	for e in intent.effects:
		if e is Effect and e.type == &"damage":
			total += e.amount
	return total


## Card text with DYNAMIC totals (owner, 2026-06-10): when `actor` is known
## (the hand), damage/block show the REAL outgoing numbers — base + the actor's
## attack stat / DEX (× stat_mult, ADR-0020) + Strength/Weak — via the exact
## battle math, so the card reads what it will actually do. Actor-less contexts
## (rewards, shop) keep the base number.
func _card_effects_summary(card: CardData, actor: Combatant = null) -> String:
	var bits: Array[String] = []
	for e in card.effects:
		if not (e is Effect):
			continue
		match e.type:
			&"damage":
				var dmg: int = e.amount
				if actor != null:
					dmg = _battle.modified_damage(actor, e.amount, true, e.stat_mult)
				bits.append("%d dmg" % dmg)
			&"block":
				var blk: int = e.amount
				if actor != null:
					blk = _battle.modified_block(actor, e.amount, true, e.stat_mult)
				bits.append("%d blk" % blk)
			&"heal": bits.append("heal %d" % e.amount)
			&"apply_status": bits.append("%d %s" % [e.stacks, e.status])
			&"draw": bits.append("draw %d" % e.amount)
			&"gain_energy": bits.append("+%d NRG" % e.amount)
			&"cleanse": bits.append("cleanse")  # ADR-0029 (antidote)
			&"gain_gold": bits.append("+%d gold" % e.amount)  # ADR-0029 (lucky coin)
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
