class_name MapView
extends Control
## The run/map screen (P2·10, run-structure.md §1/§3): turns a created party into a
## full RUN, not one fight. It generates a branching act map, lets the player pick
## a reachable node, and resolves it through the already-tested run layer:
##   combat / elite / boss -> an interactive BattleView on the run's RunController
##                            (carried HP, run deck, races, allocated stats);
##   rest                  -> heal or upgrade a card (RunController.resolve_rest);
##   event                 -> a choice with typed outcomes (resolve_event);
##   win a combat/elite     -> a card-reward draft (CardReward).
## Clearing the boss wins the run; a TPK ends it. Node-resolution LOGIC lives in
## RunNavigator (tested); this file is the asset-free view + wiring, matching
## character_creation / battle_view conventions.
##
## Set `party`, `party_races` (and optionally `run_seed`) before adding to the tree
## — the creation screen does this. Standalone, it rolls a default party + seed.

var party: Array[StringName] = [&"fighter", &"mage"]
var party_races: Dictionary = {}
var run_seed: int = 0  # 0 -> a random seed is rolled in _ready.

const DATA_DIR := "res://data"

const COL_BG := Color(0.10, 0.11, 0.15)
const COL_PANEL := Color(0.16, 0.17, 0.22)
const COL_ACCENT := Color(0.40, 0.70, 0.95)
const COL_REACH := Color(0.24, 0.38, 0.30)
const COL_DONE := Color(0.16, 0.20, 0.18)
const COL_OFF := Color(0.17, 0.18, 0.23)
const COL_DIM := Color(0.7, 0.7, 0.75)

# Friendly labels per node type.
const TYPE_LABEL := {
	&"combat": "Combat",
	&"elite": "Elite",
	&"rest": "Rest",
	&"event": "Event",
	&"boss": "BOSS",
}

## Set before adding to the tree to RESUME a saved run instead of starting fresh
## (the creation screen's "Continue" path passes the loaded RunState here).
var resume_state: RunState = null

var _db: ContentDatabase
var _controller: RunController
var _nav: RunNavigator
var _reward: CardReward

var _status_label: Label
var _map_box: VBoxContainer
var _party_box: VBoxContainer
var _overlay: Control = null

# Combat-in-progress bookkeeping (set when a BattleView is launched).
var _active_node: MapNode = null
var _active_encounter: StringName = &""
var _active_battle: EncounterBattle = null


func _ready() -> void:
	_db = ContentDatabase.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	_build_layout()
	if not result.ok:
		_status_label.text = "Content failed to load: %s" % str(result.errors)
		return

	_controller = RunController.new(_db)
	if resume_state != null:
		# Resume: drive the loaded run (party/races/deck/level/position all persisted).
		_controller.run = resume_state
		run_seed = resume_state.seed
	else:
		if run_seed == 0:
			run_seed = randi()
		_controller.start_run(party, run_seed, party_races)
		_controller.run.map = MapGenerator.new().generate(MapGenConfig.new(), run_seed)
	_nav = RunNavigator.new(_db, _controller.run)
	_reward = CardReward.new(_db, {})

	_refresh()  # also writes the initial save checkpoint


# --- Layout -----------------------------------------------------------------

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	add_child(root)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 22)
	title.text = "The Run"
	root.add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", COL_DIM)
	root.add_child(_status_label)

	# Party status strip.
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 4)
	root.add_child(_party_box)

	var sep := HSeparator.new()
	root.add_child(sep)

	# Scrollable map.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_map_box = VBoxContainer.new()
	_map_box.add_theme_constant_override("separation", 10)
	_map_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_map_box)


# --- Refresh ----------------------------------------------------------------

func _refresh() -> void:
	_refresh_status()
	_refresh_map()
	# Checkpoint the run at every node transition (saves happen between nodes; a
	# mid-combat quit rewinds to the node start). Completed runs are cleared instead.
	if _nav != null and not _nav.is_complete():
		_save_run()


func _refresh_status() -> void:
	_clear(_party_box)
	if _controller == null:
		return
	var run: RunState = _controller.run
	for cid in run.party:
		var ch: CharacterData = _db.get_character(cid)
		var name_txt: String = ch.display_name if ch != null else String(cid)
		var hp: int = int(run.party_hp.get(cid, 0))
		var lvl: int = int(run.party_level.get(cid, 1))
		var pts: int = _controller.unspent_points(cid)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(280, 0)
		var downed: String = "  (DOWNED)" if run.downed.has(cid) else ""
		lab.text = "%s   HP %d   Lv %d%s" % [name_txt, hp, lvl, downed]
		row.add_child(lab)

		if pts > 0:
			var pts_lab := Label.new()
			pts_lab.add_theme_color_override("font_color", COL_ACCENT)
			pts_lab.text = "Points: %d →" % pts
			row.add_child(pts_lab)
			for stat in [&"str", &"dex", &"con", &"int"]:
				var b := Button.new()
				b.text = String(stat).to_upper()
				b.custom_minimum_size = Vector2(48, 28)
				b.pressed.connect(_on_alloc.bind(cid, stat))
				row.add_child(b)
		_party_box.add_child(row)

	var deck := Label.new()
	deck.add_theme_color_override("font_color", COL_DIM)
	deck.text = "Run deck: %d cards" % _controller.run.run_deck.size()
	_party_box.add_child(deck)

	if not _controller.run.relics.is_empty():
		var names: Array[String] = []
		for rid in _controller.run.relics:
			var relic: RelicData = _db.get_relic(rid)
			names.append(relic.display_name if relic != null else String(rid))
		var relic_lab := Label.new()
		relic_lab.add_theme_color_override("font_color", COL_ACCENT)
		relic_lab.text = "Relics: %s" % ", ".join(names)
		_party_box.add_child(relic_lab)


func _refresh_map() -> void:
	_clear(_map_box)
	if _nav == null:
		return
	if _nav.is_complete():
		_status_label.text = "Run complete."
		return

	var reachable_ids: Dictionary = {}
	for n in _nav.reachable():
		reachable_ids[n.id] = true
	_status_label.text = "Choose your next stop." if not reachable_ids.is_empty() else "No path forward."

	# Group nodes by row, render top (row 0) to bottom (boss).
	var by_row: Dictionary = {}
	var graph: MapGraph = _nav.map()
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		var bucket: Array = by_row.get(node.row, [])
		bucket.append(node)
		by_row[node.row] = bucket
	var rows: Array = by_row.keys()
	rows.sort()

	for row_v: Variant in rows:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 10)
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		var nodes: Array = by_row[row_v]
		nodes.sort_custom(func(a: MapNode, b: MapNode) -> bool: return String(a.id) < String(b.id))
		for node: MapNode in nodes:
			row_box.add_child(_node_button(node, reachable_ids.has(node.id)))
		_map_box.add_child(row_box)


func _node_button(node: MapNode, reachable: bool) -> Button:
	var cleared: bool = _controller.run.cleared.has(node.id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 52)
	var label: String = TYPE_LABEL.get(node.node_type, String(node.node_type))
	var mark: String = ""
	if cleared:
		mark = "  ✓"
	btn.text = "%s%s" % [label, mark]
	btn.disabled = not reachable

	var col: Color = COL_OFF
	if cleared:
		col = COL_DONE
	elif reachable:
		col = COL_REACH
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	if reachable:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(2)
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	if reachable:
		btn.pressed.connect(_on_node_chosen.bind(node))
	return btn


# --- Node resolution --------------------------------------------------------

func _on_node_chosen(node: MapNode) -> void:
	if not _nav.travel_to(node.id):
		return
	match node.node_type:
		&"combat", &"elite", &"boss":
			_start_combat(node)
		&"rest":
			_show_rest(node)
		&"event":
			_show_event(node)
		_:
			# Unknown node type: nothing to resolve, just clear and move on.
			_nav.complete_current()
			_refresh()


func _start_combat(node: MapNode) -> void:
	var enc_id: StringName = _nav.encounter_for(node)
	_active_battle = _controller.begin_combat(enc_id) if enc_id != &"" else null
	if _active_battle == null:
		# No encounter available — treat the node as resolved so the run continues.
		_status_label.text = "No encounter for this node; skipping."
		_nav.complete_current()
		_refresh()
		return
	_active_node = node
	_active_encounter = enc_id

	var bv := BattleView.new()
	bv.injected_battle = _active_battle
	bv.injected_db = _db
	bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bv.combat_finished.connect(_on_combat_finished.bind(bv))
	_open_overlay(bv)


func _on_combat_finished(outcome: int, bv: BattleView) -> void:
	# Settle HP/XP via the run layer, then advance or end the run.
	_controller.finish_combat(_active_encounter, _active_battle)
	_close_overlay()
	bv.queue_free()

	var node := _active_node
	_active_node = null
	_active_battle = null
	_active_encounter = &""

	if outcome != BattleState.Outcome.WIN:
		_show_run_end(false)
		return

	_nav.complete_current()
	if _nav.is_boss(node):
		_show_run_end(true)
	elif node.node_type == &"elite":
		# Elites grant a relic (run-structure.md §5) in addition to the card draft.
		_grant_relic("elite")
		_show_reward()
	elif node.node_type == &"combat":
		_show_reward()
	else:
		_refresh()


## Award a not-yet-owned relic (deterministic pick) and tell the player. No-op if
## every relic is already owned.
func _grant_relic(source: String) -> void:
	var pool: Array[StringName] = _controller.available_relics()
	if pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ hash(_controller.run.cleared.size())
	var rid: StringName = pool[rng.randi_range(0, pool.size() - 1)]
	if _controller.grant_relic(rid, source):
		var relic: RelicData = _db.get_relic(rid)
		_status_label.text = "Relic acquired: %s — %s" % [relic.display_name, relic.description]


# --- Card reward (after a won combat/elite) ----------------------------------

func _show_reward() -> void:
	var run: RunState = _controller.run
	var offer: Array[CardData] = _reward.draft(run, CardReward.DEFAULT_CHOICES, run_seed + run.cleared.size())
	var panel := _overlay_panel("Choose a card")
	if offer.is_empty():
		var none := Label.new()
		none.text = "No cards available."
		panel.add_child(none)
	for card in offer:
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 40)
		b.text = "%s  (%d)  [%s]  %s" % [
			card.display_name, card.energy_cost,
			("neutral" if card.character_tag == &"neutral" else String(card.character_tag)),
			_card_summary(card),
		]
		b.pressed.connect(_on_reward_pick.bind(card.id))
		panel.add_child(b)
	var skip := Button.new()
	skip.text = "Skip"
	skip.custom_minimum_size = Vector2(120, 34)
	skip.pressed.connect(_on_reward_skip)
	panel.add_child(skip)


func _on_reward_pick(card_id: StringName) -> void:
	_reward.pick(_controller.run, card_id)
	_close_overlay()
	_refresh()


func _on_reward_skip() -> void:
	_reward.skip(_controller.run)
	_close_overlay()
	_refresh()


# --- Rest -------------------------------------------------------------------

func _show_rest(node: MapNode) -> void:
	var panel := _overlay_panel("Rest")
	var heal := Button.new()
	heal.custom_minimum_size = Vector2(360, 38)
	heal.text = "Heal the party (+%d HP each)" % _db.get_battle_config().rest_heal
	heal.pressed.connect(_on_rest_heal)
	panel.add_child(heal)

	var up_label := Label.new()
	up_label.add_theme_color_override("font_color", COL_DIM)
	up_label.text = "…or upgrade a card:"
	panel.add_child(up_label)

	var any: bool = false
	var seen: Dictionary = {}
	for card_id in _controller.run.run_deck:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		var upgrade: CardData = _db.get_upgrade_for(card_id)
		if upgrade == null:
			continue
		any = true
		var base: CardData = _db.get_card(card_id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 34)
		var base_name: String = base.display_name if base != null else String(card_id)
		b.text = "%s → %s" % [base_name, upgrade.display_name]
		b.pressed.connect(_on_rest_upgrade.bind(card_id))
		panel.add_child(b)
	if not any:
		var none := Label.new()
		none.add_theme_color_override("font_color", COL_DIM)
		none.text = "(no upgradeable cards)"
		panel.add_child(none)


func _on_rest_heal() -> void:
	_controller.resolve_rest(&"heal")
	_nav.complete_current()
	_close_overlay()
	_refresh()


func _on_rest_upgrade(card_id: StringName) -> void:
	_controller.resolve_rest(&"upgrade", card_id)
	_nav.complete_current()
	_close_overlay()
	_refresh()


# --- Event ------------------------------------------------------------------

func _show_event(node: MapNode) -> void:
	var ev_id: StringName = _nav.event_for(node)
	var ev: EventData = _db.get_event(ev_id)
	if ev == null:
		_nav.complete_current()
		_refresh()
		return
	var panel := _overlay_panel(ev.title if ev.title != "" else "Event")
	if ev.body != "":
		var body := Label.new()
		body.add_theme_color_override("font_color", COL_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.custom_minimum_size = Vector2(420, 0)
		body.text = ev.body
		panel.add_child(body)
	for i in ev.choices.size():
		var choice: EventChoice = ev.choices[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 36)
		b.text = choice.label
		b.pressed.connect(_on_event_choice.bind(ev_id, i))
		panel.add_child(b)


func _on_event_choice(ev_id: StringName, index: int) -> void:
	_controller.resolve_event(ev_id, index)
	_nav.complete_current()
	_close_overlay()
	_refresh()


# --- Leveling allocation ----------------------------------------------------

func _on_alloc(cid: StringName, stat: StringName) -> void:
	_controller.allocate_stat_point(cid, stat)
	_refresh_status()


# --- Run end ----------------------------------------------------------------

func _show_run_end(victory: bool) -> void:
	_clear_save()  # the run is over — don't offer to resume it
	var panel := _overlay_panel("VICTORY — the act is cleared!" if victory else "DEFEAT — the party fell.")
	var summary := Label.new()
	summary.add_theme_color_override("font_color", COL_DIM)
	var run: RunState = _controller.run
	summary.text = "Nodes cleared: %d   |   Run deck: %d cards" % [run.cleared.size(), run.run_deck.size()]
	panel.add_child(summary)

	var again := Button.new()
	again.text = "New Run"
	again.custom_minimum_size = Vector2(160, 40)
	again.pressed.connect(_on_new_run)
	panel.add_child(again)


func _on_new_run() -> void:
	_clear_save()
	var creation := CharacterCreation.new()
	creation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(creation)
	queue_free()


# --- Save / resume (P2·02 wiring) -------------------------------------------

## Persist the run to the default save slot (between-node checkpoint).
func _save_run() -> void:
	if _controller != null and _controller.run != null:
		_controller.run.save_to()


## Remove the save when the run ends (win/defeat/abandon) so it isn't resumable.
func _clear_save() -> void:
	if FileAccess.file_exists(RunState.DEFAULT_SAVE_PATH):
		DirAccess.remove_absolute(RunState.DEFAULT_SAVE_PATH)


# --- Overlay helpers --------------------------------------------------------

## Dim the map and show `content` centered; only one overlay exists at a time.
func _open_overlay(content: Control) -> void:
	_close_overlay()
	var scrim := Control.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(dim)
	scrim.add_child(content)
	add_child(scrim)
	_overlay = scrim


## A centered panel overlay with a title; returns the VBox to add controls into.
func _overlay_panel(title: String) -> VBoxContainer:
	var scrim := Control.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(center)

	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	center.add_child(pc)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pc.add_child(box)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", COL_ACCENT)
	head.text = title
	box.add_child(head)

	_close_overlay()
	add_child(scrim)
	_overlay = scrim
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


# --- Helpers ----------------------------------------------------------------

func _card_summary(card: CardData) -> String:
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
	return ", ".join(bits)


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
		node.remove_child(child)
