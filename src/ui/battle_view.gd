class_name BattleView
extends Control
## The first PLAYABLE, code-driven battle scene for the prototype (task P1·10).
##
## It is a thin PRESENTATION + INPUT layer over the already-built combat spine —
## it owns no game rules. Everything it shows or mutates routes through the public
## APIs of the systems it wires (ContentDatabase, EncounterAssembler,
## EncounterBattle/BattleState, CardPlay, Deck, EnemyAI, GridModel, Pathfinder).
## No image assets are used: tiles, units, cards and banners are ColorRect /
## Panel / Label / Button / Line2D plus a Node2D `_draw` overlay for the grid.
##
## Flow (_ready):
##   1. Load /data via ContentDatabase. On failure, the errors are shown on screen
##      and nothing else is built (a fatal load is fatal, per the loader contract).
##   2. Assemble `skirmish_01` with party [vanguard, mage] via EncounterAssembler.
##   3. Wrap the battle in a CardPlay, shuffle the deck, start the player turn,
##      pre-select enemy telegraphs, then build + refresh the UI.
##
## Input is mouse-first but routed through small intent helpers (_on_tile_clicked,
## _on_unit_clicked, _arm_card, _arm_innate, _request_end_turn, _request_restart)
## so a gamepad layer (ADR-0008) can drive the same intents later without touching
## presentation.
##
## Interaction model (see the report): click a player unit to select it; click a
## hand card or a Strike/Defend button to ARM it, then click a target tile/unit to
## play it (validated by CardPlay; the rejection reason is surfaced briefly). With
## a unit selected and nothing armed, clicking a reachable tile MOVES it. End Turn
## runs the enemy phase; when the outcome is decided a Victory/Defeat banner with a
## Restart button appears.

# --- Tunables for the VIEW only (layout, not game balance) -------------------
# These are presentation constants (pixel sizes / colours), not balance numbers,
# so they live here rather than in /data (ADR-0003 governs balance, not layout).
const TILE_PX: float = 72.0
const GRID_ORIGIN: Vector2 = Vector2(40.0, 96.0)
const UNIT_RADIUS: float = 26.0

# Bottom-HUD vertical layout (offsets are from the bottom edge, so negative).
# Two clearly separated rows: the innate action bar sits ABOVE the hand row with a
# visible gap, and neither shares space with the top-bar End Turn button.
const ACTION_BAR_TOP: float = -154.0   # Strike / Defend row top (40px tall buttons)
const HAND_ROW_TOP: float = -96.0      # hand row top (72px tall cards) → 18px gap
const HUD_LEFT_INSET: float = 40.0     # left inset shared by both HUD rows

const COLOR_TILE: Color = Color(0.16, 0.17, 0.22)
const COLOR_TILE_ALT: Color = Color(0.13, 0.14, 0.19)
const COLOR_TILE_BLOCKED: Color = Color(0.30, 0.10, 0.10)
const COLOR_GRID_LINE: Color = Color(0.30, 0.32, 0.40)
const COLOR_REACHABLE: Color = Color(0.20, 0.45, 0.65, 0.45)
const COLOR_TARGETABLE: Color = Color(0.65, 0.55, 0.15, 0.45)
const COLOR_PLAYER: Color = Color(0.25, 0.55, 0.85)
const COLOR_ENEMY: Color = Color(0.80, 0.30, 0.30)
const COLOR_SELECTED: Color = Color(0.95, 0.85, 0.30)
const COLOR_HP: Color = Color(0.30, 0.80, 0.35)
const COLOR_BLOCK: Color = Color(0.55, 0.70, 0.95)
const COLOR_INTENT_BG: Color = Color(0.05, 0.05, 0.08, 0.85)
const COLOR_INTENT_BORDER: Color = Color(0.55, 0.45, 0.20, 0.90)
const COLOR_INTENT_TEXT: Color = Color(1.0, 0.85, 0.4)

const DATA_DIR: String = "res://data"
const ENCOUNTER_ID: StringName = &"skirmish_01"
const STRIKE_ID: StringName = &"strike"
const DEFEND_ID: StringName = &"defend"
const RNG_SEED: int = 1


# --- Owned runtime references ------------------------------------------------
var _db: ContentDatabase = null
var _battle: EncounterBattle = null
var _card_play: CardPlay = null

# Selection / arming state. Exactly one of `_armed_card` / `_armed_innate` is set
# while a card is armed; both null means "movement mode" for the selected unit.
var _selected: Combatant = null
var _armed_card: CardData = null      # a drawn hand card awaiting a target
var _armed_innate: CardData = null    # an innate (strike/defend) awaiting a target
var _status_text: String = ""         # transient feedback (rejections, hints)

# Cached reachable tiles for the selected unit (Vector2i -> cost). Recomputed on
# selection / after any move so movement highlighting stays in sync.
var _reachable: Dictionary = {}

# --- Node references (built in code) ----------------------------------------
var _board: Node2D = null             # the grid/unit `_draw` surface
var _hud_layer: Control = null        # holds hand row, energy, action bar, buttons
var _hand_row: HBoxContainer = null
var _energy_label: Label = null
var _turn_label: Label = null
var _status_label: Label = null
var _strike_button: Button = null
var _defend_button: Button = null
var _end_turn_button: Button = null
var _banner_layer: Control = null     # win/loss overlay (hidden until decided)
var _error_label: Label = null        # shown only when the data load fails


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_db = ContentDatabase.new()
	var load_result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	if not load_result.ok:
		_show_load_errors(load_result)
		return
	_build_static_ui()
	_start_encounter()


# ============================================================================
#  Encounter lifecycle
# ============================================================================

## Assemble (or re-assemble) the encounter and begin the first player turn.
## Shared by the initial boot and the Restart button so a battle can be replayed
## from a clean state without reloading /data.
func _start_encounter() -> void:
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	if encounter == null:
		_status_text = "Missing encounter '%s'" % ENCOUNTER_ID
		_refresh()
		return

	var assembler: EncounterAssembler = EncounterAssembler.new()
	var party: Array[StringName] = [&"vanguard", &"mage"]
	_battle = assembler.build(encounter, _db, party, RNG_SEED)
	_card_play = CardPlay.new(_battle)

	# Reset transient view state.
	_selected = null
	_armed_card = null
	_armed_innate = null
	_status_text = "Select a unit, then a card or move."
	_reachable = {}

	# The assembler leaves the deck assembled-but-unshuffled; shuffle before the
	# first draw so the opening hand is randomised (a presentation choice; the
	# combat spine works either way).
	_battle.deck.start_battle()
	_battle.start_player_turn()
	_refresh_telegraphs()
	_auto_select_first_player()
	_hide_banner()
	_refresh()


## Pick a sensible default selection so the player can act immediately.
func _auto_select_first_player() -> void:
	var players: Array[Combatant] = _battle.living_players()
	if not players.is_empty():
		_select_unit(players[0])


## Re-run intent selection for every living enemy so their telegraphs are
## populated for display this player turn. The AI clears a telegraph after the
## enemy acts, so this is called again at each player-turn start.
func _refresh_telegraphs() -> void:
	if _battle == null or _battle.enemy_ai == null:
		return
	for enemy in _battle.living_enemies():
		var data: EnemyData = enemy.source_data as EnemyData
		if data != null:
			_battle.enemy_ai.select_intent(enemy, data, _battle)


# ============================================================================
#  Static UI construction (built once)
# ============================================================================

func _build_static_ui() -> void:
	# The board: a Node2D whose _draw paints tiles, highlights and units. A custom
	# draw surface keeps the grid cheap and asset-free.
	_board = Node2D.new()
	_board.name = "Board"
	_board.draw.connect(_draw_board)
	add_child(_board)

	# Top read-outs (left side of the top bar).
	_turn_label = _make_label(Vector2(40, 16), 220)
	add_child(_turn_label)
	_energy_label = _make_label(Vector2(280, 16), 240)
	add_child(_energy_label)
	_status_label = _make_label(Vector2(40, 48), 900)
	add_child(_status_label)

	# End Turn lives ALONE in the top-right corner so it is always visible and never
	# shares space with the hand or the innate action bar. Anchored to the top-right
	# edge so it tracks the corner on windows larger than 1280×800.
	_end_turn_button = Button.new()
	_end_turn_button.name = "EndTurnButton"
	_end_turn_button.text = "End Turn"
	_end_turn_button.custom_minimum_size = Vector2(160, 44)
	_end_turn_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_end_turn_button.offset_left = -200.0
	_end_turn_button.offset_top = 14.0
	_end_turn_button.offset_right = -40.0
	_end_turn_button.offset_bottom = 58.0
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	add_child(_end_turn_button)

	# HUD container anchored to the bottom holds the action bar and hand row.
	_hud_layer = Control.new()
	_hud_layer.name = "Hud"
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(_hud_layer)

	_build_action_bar()
	_build_hand_row()

	# Win/loss banner overlay, hidden until an outcome is decided.
	_build_banner()


## The innate action bar: Strike / Defend for the selected unit. Its OWN row, set
## clearly above the hand row (see ACTION_BAR_TOP / HAND_ROW_TOP). End Turn is not
## here — it lives alone in the top-right corner.
func _build_action_bar() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.name = "ActionBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = HUD_LEFT_INSET
	bar.offset_top = ACTION_BAR_TOP
	bar.add_theme_constant_override("separation", 12)
	_hud_layer.add_child(bar)

	_strike_button = Button.new()
	_strike_button.text = "Strike"
	_strike_button.custom_minimum_size = Vector2(120, 40)
	_strike_button.pressed.connect(_on_strike_pressed)
	bar.add_child(_strike_button)

	_defend_button = Button.new()
	_defend_button.text = "Defend"
	_defend_button.custom_minimum_size = Vector2(120, 40)
	_defend_button.pressed.connect(_on_defend_pressed)
	bar.add_child(_defend_button)


## The hand row: clickable card panels rebuilt on every refresh (hand contents
## change as cards are played / drawn).
func _build_hand_row() -> void:
	_hand_row = HBoxContainer.new()
	_hand_row.name = "HandRow"
	_hand_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hand_row.offset_left = HUD_LEFT_INSET
	_hand_row.offset_top = HAND_ROW_TOP
	_hand_row.add_theme_constant_override("separation", 14)
	_hud_layer.add_child(_hand_row)


## The centered Victory/Defeat banner with a Restart button. Built hidden.
func _build_banner() -> void:
	_banner_layer = Control.new()
	_banner_layer.name = "Banner"
	_banner_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner_layer.visible = false
	add_child(_banner_layer)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner_layer.add_child(dim)

	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "BannerPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 20)
	_banner_layer.add_child(panel)

	var title: Label = Label.new()
	title.name = "BannerTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	panel.add_child(title)

	var restart: Button = Button.new()
	restart.name = "RestartButton"
	restart.text = "Restart"
	restart.custom_minimum_size = Vector2(200, 56)
	restart.pressed.connect(_on_restart_pressed)
	panel.add_child(restart)


## Build a plain Label at `pos` with a fixed width.
func _make_label(pos: Vector2, width: float) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.custom_minimum_size = Vector2(width, 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ============================================================================
#  Refresh — pull current battle state into the UI
# ============================================================================

## Re-read the battle and update every dynamic widget. Called after any action.
func _refresh() -> void:
	if _battle == null:
		return
	_turn_label.text = "Turn %d" % _battle.turn_number
	_energy_label.text = "Energy: %d / %d" % [_battle.energy, _battle.config.energy_per_turn]
	_status_label.text = _status_text

	var has_selection: bool = _selected != null and _selected.is_alive()
	_strike_button.disabled = not has_selection
	_defend_button.disabled = not has_selection
	_strike_button.button_pressed = _armed_innate != null and _armed_innate.id == STRIKE_ID
	_defend_button.button_pressed = _armed_innate != null and _armed_innate.id == DEFEND_ID

	_rebuild_hand()
	if _board != null:
		_board.queue_redraw()
	_evaluate_outcome()


## Rebuild the clickable hand row from the deck's current hand.
func _rebuild_hand() -> void:
	for child in _hand_row.get_children():
		child.queue_free()
	if _battle == null:
		return
	for card in _battle.deck.hand:
		_hand_row.add_child(_make_card_button(card))


## One clickable card "tile": name, cost and short effect text on a Panel-backed
## Button. Armed cards and unaffordable cards are visually distinguished.
func _make_card_button(card: CardData) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(150, 72)
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD
	var affordable: bool = card.energy_cost <= _battle.energy
	var armed: bool = _armed_card == card
	var prefix: String = "> " if armed else ""
	button.text = "%s%s  [%d]\n%s" % [
		prefix, card.display_name, card.energy_cost, _short_effect_text(card)
	]
	button.disabled = not affordable and not armed
	button.pressed.connect(_on_card_pressed.bind(card))
	return button


## A compact human-readable summary of a card's effects for the hand tile.
func _short_effect_text(card: CardData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for effect in card.effects:
		parts.append(_effect_summary(effect))
	return ", ".join(parts)


## Summarise a single Effect (no balance logic — pure display formatting).
func _effect_summary(effect: Effect) -> String:
	match effect.type:
		&"damage":
			return "DMG %d" % effect.amount
		&"block":
			return "BLK %d" % effect.amount
		&"heal":
			return "HEAL %d" % effect.amount
		&"apply_status":
			return "%s %d" % [String(effect.status).to_upper(), effect.stacks]
		&"move":
			return "MOVE"
		&"push":
			return "PUSH %d" % effect.amount
		&"draw":
			return "DRAW %d" % effect.amount
		&"gain_energy":
			return "NRG %d" % effect.amount
		_:
			return String(effect.type)


# ============================================================================
#  Drawing the board (tiles, highlights, units, intents)
# ============================================================================

func _draw_board() -> void:
	if _battle == null:
		return
	var grid: GridModel = _battle.grid
	_draw_tiles(grid)
	_draw_highlights(grid)
	_draw_units()


## Paint the base grid: checkered tiles, blocked tiles in a warning colour, plus
## the cell borders.
func _draw_tiles(grid: GridModel) -> void:
	for y in range(grid.size.y):
		for x in range(grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = _cell_rect(cell)
			var fill: Color = COLOR_TILE if (x + y) % 2 == 0 else COLOR_TILE_ALT
			if grid.is_blocked(cell):
				fill = COLOR_TILE_BLOCKED
			_board.draw_rect(rect, fill, true)
			_board.draw_rect(rect, COLOR_GRID_LINE, false, 1.0)


## Overlay movement / target highlights for the current selection + arming mode.
func _draw_highlights(grid: GridModel) -> void:
	if _selected == null or not _selected.is_alive():
		return
	if _armed_card != null or _armed_innate != null:
		_draw_target_highlights(grid)
	else:
		_draw_reachable_highlights()


## Highlight every tile the selected unit can move to this action.
func _draw_reachable_highlights() -> void:
	for key in _reachable.keys():
		var cell: Vector2i = key
		if cell == _selected.grid_position:
			continue
		_board.draw_rect(_cell_rect(cell), COLOR_REACHABLE, true)


## Highlight tiles within the armed card's range so the player sees where it can
## be aimed (orthogonal/Manhattan range, matching CardPlay's validation).
func _draw_target_highlights(grid: GridModel) -> void:
	var spec: TargetSpec = _armed_target_spec()
	if spec == null:
		return
	var origin: Vector2i = _selected.grid_position
	for y in range(grid.size.y):
		for x in range(grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
			var dist: int = abs(cell.x - origin.x) + abs(cell.y - origin.y)
			if dist <= spec.range:
				_board.draw_rect(_cell_rect(cell), COLOR_TARGETABLE, true)


## Draw each living combatant as a coloured disc with HP / block labels and, for
## enemies, the telegraph of their upcoming intent.
func _draw_units() -> void:
	var default_font: Font = get_theme_default_font()
	var font_size: int = 16
	# Each unit's labels are CENTRED over its own tile within a box one tile wide,
	# so adjacent units' name / HP / intent text stay over their own token and don't
	# bleed into a neighbour. Vertical bands keep name (above) and HP (below) from
	# colliding with the token or with each other.
	var label_box_w: float = TILE_PX
	for unit in _battle.combatants:
		if not unit.is_alive():
			continue
		var center: Vector2 = _cell_center(unit.grid_position)
		var box_x: float = center.x - label_box_w * 0.5
		var body: Color = COLOR_PLAYER if unit.is_player() else COLOR_ENEMY
		_board.draw_circle(center, UNIT_RADIUS, body)
		if unit == _selected:
			_board.draw_arc(center, UNIT_RADIUS + 4.0, 0.0, TAU, 32, COLOR_SELECTED, 3.0)

		# HP / block read-out centred just BELOW the disc.
		var hp_text: String = "%d/%d" % [unit.hp, unit.max_hp]
		if unit.block > 0:
			hp_text += "  +%d" % unit.block
		var hp_pos: Vector2 = Vector2(box_x, center.y + UNIT_RADIUS + 16.0)
		var hp_color: Color = COLOR_BLOCK if unit.block > 0 else COLOR_HP
		_board.draw_string(default_font, hp_pos, hp_text, HORIZONTAL_ALIGNMENT_CENTER, label_box_w, font_size, hp_color)

		# Name centred just ABOVE the disc.
		var name_pos: Vector2 = Vector2(box_x, center.y - UNIT_RADIUS - 12.0)
		_board.draw_string(default_font, name_pos, unit.display_name, HORIZONTAL_ALIGNMENT_CENTER, label_box_w, font_size, Color.WHITE)

		# Enemy intent telegraph sits ABOVE the name on its own dark panel so it
		# stays legible over the board and never overlaps the name or an adjacent
		# unit's label.
		if unit.is_enemy():
			var intent_text: String = _telegraph_text(unit)
			if intent_text != "":
				_draw_intent_badge(default_font, font_size, center, intent_text)


## Draw an enemy's intent telegraph as centred text on a small dark rounded panel,
## floated above the unit's name band so it reads clearly over the board and never
## collides with the name, the token, or a neighbouring unit's labels.
func _draw_intent_badge(font: Font, font_size: int, center: Vector2, text: String) -> void:
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad: Vector2 = Vector2(8.0, 4.0)
	var badge_size: Vector2 = text_size + pad * 2.0
	# Sits above the name band (name top ≈ center.y - UNIT_RADIUS - 28).
	var badge_top: float = center.y - UNIT_RADIUS - 28.0 - badge_size.y
	var badge_pos: Vector2 = Vector2(center.x - badge_size.x * 0.5, badge_top)
	var badge_rect: Rect2 = Rect2(badge_pos, badge_size)
	_board.draw_rect(badge_rect, COLOR_INTENT_BG, true)
	_board.draw_rect(badge_rect, COLOR_INTENT_BORDER, false, 1.0)
	var text_pos: Vector2 = Vector2(badge_pos.x + pad.x, badge_pos.y + pad.y + font.get_ascent(font_size))
	_board.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_INTENT_TEXT)


## The icon-ish telegraph string for an enemy ("ATK 6", "BLOCK", …), read from
## the EnemyAI's stored telegraph. Empty when nothing is telegraphed.
func _telegraph_text(enemy: Combatant) -> String:
	if _battle.enemy_ai == null:
		return ""
	var telegraph: EnemyAI.Telegraph = _battle.enemy_ai.get_telegraph(enemy)
	if telegraph == null or telegraph.intent == null:
		return ""
	var intent: IntentData = telegraph.intent
	var icon: String = String(intent.telegraph).to_upper()
	# Surface the headline magnitude (first damage/block effect) for readability.
	for effect in intent.effects:
		if effect.type == &"damage":
			return "ATK %d" % effect.amount
		if effect.type == &"block":
			return "BLOCK %d" % effect.amount
	return icon


# ============================================================================
#  Coordinate mapping (view-local; mirrors GridModel's cell<->world contract)
# ============================================================================

## Top-left pixel rect of a cell on the board.
func _cell_rect(cell: Vector2i) -> Rect2:
	var top_left: Vector2 = GRID_ORIGIN + Vector2(float(cell.x) * TILE_PX, float(cell.y) * TILE_PX)
	return Rect2(top_left, Vector2(TILE_PX, TILE_PX))


## Pixel center of a cell.
func _cell_center(cell: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2((float(cell.x) + 0.5) * TILE_PX, (float(cell.y) + 0.5) * TILE_PX)


## The cell under a board-local pixel position, or null when outside the grid.
func _cell_at_point(point: Vector2) -> Variant:
	if _battle == null:
		return null
	var local: Vector2 = point - GRID_ORIGIN
	if local.x < 0.0 or local.y < 0.0:
		return null
	var cell: Vector2i = Vector2i(int(local.x / TILE_PX), int(local.y / TILE_PX))
	if not _battle.grid.in_bounds(cell):
		return null
	return cell


# ============================================================================
#  Input — mouse-first, routed through intent helpers (gamepad-ready, ADR-0008)
# ============================================================================

## Capture left-clicks on the board area. HUD buttons consume their own clicks
## (Control event propagation), so anything reaching here is a board click.
func _gui_input(event: InputEvent) -> void:
	if _battle == null:
		return
	if _banner_layer != null and _banner_layer.visible:
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var cell: Variant = _cell_at_point(mouse.position)
			if cell != null:
				var tile: Vector2i = cell
				_handle_board_click(tile)
				accept_event()


## Resolve a click on tile `tile`: if a unit stands there it is a unit-click,
## otherwise it is a tile-click. This is the single board-input intent the
## (future) gamepad cursor would also call.
func _handle_board_click(tile: Vector2i) -> void:
	var occupant: Variant = _battle.grid.get_occupant(tile)
	if occupant is Combatant and (occupant as Combatant).is_alive():
		_on_unit_clicked(occupant as Combatant, tile)
	else:
		_on_tile_clicked(tile)


## A unit was clicked. If a card/innate is armed, the unit is the target;
## otherwise selecting a player unit (re)selects it. Clicking an enemy with
## nothing armed is a no-op hint.
func _on_unit_clicked(unit: Combatant, tile: Vector2i) -> void:
	if _armed_card != null or _armed_innate != null:
		_play_armed_at(unit, tile)
		return
	if unit.is_player():
		_select_unit(unit)
		_status_text = "Selected %s." % unit.display_name
	else:
		_status_text = "%s is an enemy. Select one of your units." % unit.display_name
	_refresh()


## A bare tile (no living unit) was clicked. If a card/innate is armed, play it at
## the tile; otherwise treat it as a movement request for the selected unit.
func _on_tile_clicked(tile: Vector2i) -> void:
	if _armed_card != null or _armed_innate != null:
		_play_armed_at(tile, tile)
		return
	if _selected != null and _selected.is_alive():
		_try_move(tile)
	else:
		_status_text = "Select a unit first."
		_refresh()


# --- Selection --------------------------------------------------------------

## Make `unit` the active selection, clear any armed action, and recompute its
## reachable tiles for movement highlighting.
func _select_unit(unit: Combatant) -> void:
	_selected = unit
	_armed_card = null
	_armed_innate = null
	_recompute_reachable()


## Recompute the reachable-tile set for the selected unit within its move_range,
## treating other units as obstacles (block_occupied) so movement matches what a
## real move would allow.
func _recompute_reachable() -> void:
	_reachable = {}
	if _selected == null or not _selected.is_alive() or _battle == null:
		return
	var pathfinder: Pathfinder = Pathfinder.new(_battle.grid)
	_reachable = pathfinder.reachable_tiles(_selected.grid_position, _selected.move_range, true)


# --- Movement ---------------------------------------------------------------

## Attempt to move the selected unit to `tile` if it is within the reachable set.
## Movement commits through BattleState.move_unit so the grid stays in sync.
func _try_move(tile: Vector2i) -> void:
	if _selected == null:
		return
	if tile == _selected.grid_position:
		_status_text = "%s is already there." % _selected.display_name
		_refresh()
		return
	if not _reachable.has(tile):
		_status_text = "Tile out of move range."
		_refresh()
		return
	if _battle.grid.is_occupied(tile) or _battle.grid.is_blocked(tile):
		_status_text = "Tile is occupied or blocked."
		_refresh()
		return
	_battle.move_unit(_selected, tile)
	_recompute_reachable()
	_status_text = "%s moved." % _selected.display_name
	_refresh()


# --- Arming + playing cards -------------------------------------------------

## Hand card pressed: arm it (awaiting a target) or, if it self-targets / needs no
## explicit target, play it immediately on the selected unit.
func _on_card_pressed(card: CardData) -> void:
	if _selected == null or not _selected.is_alive():
		_status_text = "Select a unit before playing a card."
		_refresh()
		return
	_arm_card(card)


## Arm a drawn hand card. Self-targeting cards resolve immediately on the selected
## unit; everything else waits for a target click.
func _arm_card(card: CardData) -> void:
	_armed_innate = null
	if _armed_card == card:
		# Toggling the same card disarms it.
		_armed_card = null
		_status_text = "Disarmed %s." % card.display_name
		_refresh()
		return
	_armed_card = card
	if _is_self_target(card):
		_play_armed_at(_selected, _selected.grid_position)
		return
	_status_text = "Aim %s: click a target." % card.display_name
	_refresh()


## Strike button: arm the selected unit's innate Strike.
func _on_strike_pressed() -> void:
	_arm_innate(STRIKE_ID)


## Defend button: arm the selected unit's innate Defend.
func _on_defend_pressed() -> void:
	_arm_innate(DEFEND_ID)


## Arm an innate action by id (resolved through the database). Self-targeting
## innates (Defend) resolve immediately; targeted ones (Strike) await a click.
func _arm_innate(innate_id: StringName) -> void:
	if _selected == null or not _selected.is_alive():
		_status_text = "Select a unit before using an action."
		_refresh()
		return
	var card: CardData = _db.get_card(innate_id)
	if card == null:
		_status_text = "Missing innate '%s'." % innate_id
		_refresh()
		return
	_armed_card = null
	if _armed_innate != null and _armed_innate.id == innate_id:
		_armed_innate = null
		_status_text = "Disarmed %s." % card.display_name
		_refresh()
		return
	_armed_innate = card
	if _is_self_target(card):
		_play_armed_at(_selected, _selected.grid_position)
		return
	_status_text = "Aim %s: click a target." % card.display_name
	_refresh()


## Resolve the currently armed card/innate against `target` (a Combatant or a
## Vector2i tile). Routes to CardPlay.play_card / play_innate, surfaces the result
## reason on rejection, and on success clears arming + refreshes (re-selecting
## stays on the same unit so the player can chain actions).
func _play_armed_at(target: Variant, tile: Vector2i) -> void:
	if _selected == null or not _selected.is_alive():
		return
	var result: CardPlay.PlayResult = null
	if _armed_innate != null:
		result = _card_play.play_innate(_selected, _armed_innate, _resolve_target(_armed_innate, target, tile))
	elif _armed_card != null:
		result = _card_play.play_card(_selected, _armed_card, _resolve_target(_armed_card, target, tile))
	else:
		return

	if result == null:
		return
	if not result.ok:
		_status_text = result.reason
		# Keep the card armed so the player can retry a different target.
		_refresh()
		return

	# Success: disarm and refresh. The selection's reachable set may have changed
	# (e.g. a move/push effect), so recompute it.
	_armed_card = null
	_armed_innate = null
	_status_text = "Played."
	_recompute_reachable()
	_refresh()


## Choose the argument to hand CardPlay for `card`: tile-typed targets want the
## Vector2i tile; unit-typed targets want the Combatant (falling back to the tile
## when the click landed on empty ground, which CardPlay will then reject cleanly).
func _resolve_target(card: CardData, clicked: Variant, tile: Vector2i) -> Variant:
	var spec: TargetSpec = card.target
	if spec == null:
		return tile
	match spec.target_type:
		&"tile", &"empty_tile":
			return tile
		&"self":
			return _selected
		_:
			# Unit-typed: prefer a clicked Combatant; otherwise pass the tile so the
			# validator returns a precise "must target a unit" reason.
			if clicked is Combatant:
				return clicked
			return tile


## Whether a card's TargetSpec targets the acting unit itself (range 0 / self).
func _is_self_target(card: CardData) -> bool:
	var spec: TargetSpec = card.target
	return spec != null and spec.target_type == &"self"


## The TargetSpec of whatever is currently armed (for range highlighting).
func _armed_target_spec() -> TargetSpec:
	if _armed_innate != null:
		return _armed_innate.target
	if _armed_card != null:
		return _armed_card.target
	return null


# --- End turn / restart -----------------------------------------------------

func _on_end_turn_pressed() -> void:
	_request_end_turn()


## End the player turn: run the enemy phase via BattleState, then (if the battle
## continues) begin a fresh player turn and re-telegraph enemy intents.
func _request_end_turn() -> void:
	if _battle == null:
		return
	if _battle.check_outcome() != BattleState.Outcome.ONGOING:
		return
	_armed_card = null
	_armed_innate = null
	_battle.end_player_turn()

	# The enemy phase may have ended the battle; only roll a new player turn if not.
	if _battle.check_outcome() == BattleState.Outcome.ONGOING:
		_battle.start_player_turn()
		_refresh_telegraphs()
		_status_text = "Your turn."
		# Keep the selection if it is still alive; otherwise pick a new one.
		if _selected == null or not _selected.is_alive():
			_selected = null
			_auto_select_first_player()
		else:
			_recompute_reachable()
	_refresh()


func _on_restart_pressed() -> void:
	_request_restart()


## Rebuild the encounter from scratch (Restart button).
func _request_restart() -> void:
	_start_encounter()


# ============================================================================
#  Outcome / banner
# ============================================================================

## Check the battle outcome and show the win/loss banner when it is decided.
func _evaluate_outcome() -> void:
	if _battle == null:
		return
	var outcome: BattleState.Outcome = _battle.check_outcome()
	match outcome:
		BattleState.Outcome.WIN:
			_show_banner("Victory")
		BattleState.Outcome.LOSS:
			_show_banner("Defeat")
		_:
			_hide_banner()


func _show_banner(title: String) -> void:
	if _banner_layer == null:
		return
	var label: Label = _banner_layer.get_node("BannerPanel/BannerTitle") as Label
	if label != null:
		label.text = title
	_banner_layer.visible = true


func _hide_banner() -> void:
	if _banner_layer != null:
		_banner_layer.visible = false


# ============================================================================
#  Load-failure surface
# ============================================================================

## Render the loader's collected errors on screen and stop (a failed load is
## fatal, per the ContentDatabase contract). No battle is built.
func _show_load_errors(result: ContentDatabase.LoadResult) -> void:
	_error_label = Label.new()
	_error_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Failed to load content from %s:" % DATA_DIR)
	for err in result.errors:
		lines.append("  - " + err)
	_error_label.text = "\n".join(lines)
	add_child(_error_label)
