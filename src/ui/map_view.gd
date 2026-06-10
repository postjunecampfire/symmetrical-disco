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

# StS-style parchment palette (owner reference screenshots, 2026-06-10).
const COL_BG := Color(0.13, 0.11, 0.10)          # dark room around the map sheet
const COL_PARCHMENT := Color(0.78, 0.74, 0.64)   # the map sheet
const COL_INK := Color(0.22, 0.19, 0.15)         # node glyphs / edges / text on parchment
const COL_INK_DIM := Color(0.22, 0.19, 0.15, 0.45)
const COL_PANEL := Color(0.16, 0.17, 0.22)
const COL_ACCENT := Color(0.72, 0.18, 0.16)      # reachable marker (StS red)
const COL_REACH := Color(0.72, 0.18, 0.16)
const COL_DONE := Color(0.35, 0.45, 0.32)
const COL_OFF := Color(0.17, 0.18, 0.23)
const COL_DIM := Color(0.45, 0.40, 0.33)

# Friendly labels per node type.
const TYPE_LABEL := {
	&"combat": "Combat",
	&"elite": "Elite",
	&"rest": "Rest",
	&"event": "Event",
	&"shop": "Merchant",
	&"treasure": "Treasure",
	&"boss": "BOSS",
}

## Set before adding to the tree to RESUME a saved run instead of starting fresh
## (the creation screen's "Continue" path passes the loaded RunState here).
var resume_state: RunState = null

var _db: ContentDatabase
var _controller: RunController
var _nav: RunNavigator
var _reward: CardReward
var _meta: MetaState
var _meta_progress: MetaProgress

## VBox that also draws the dashed inter-node paths (StS look): segments are in
## ITS local space, rebuilt (deferred, post-layout) on every map refresh.
class MapSheet extends VBoxContainer:
	var segments: Array = []  # Array of [Vector2 from, Vector2 to]
	var ink: Color = Color(0.22, 0.19, 0.15, 0.8)

	func _draw() -> void:
		for seg: Variant in segments:
			draw_dashed_line(seg[0], seg[1], ink, 2.0, 7.0)


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

	var logger := TelemetryLogger.new()
	if OS.has_feature("editor"):
		# Running from source: write telemetry into the project folder (gitignored
		# telemetry_dump/) so playtest runs are analyzable without copying out of
		# user://. Exported builds keep the user:// default.
		logger.base_dir = "res://telemetry_dump"
	_controller = RunController.new(_db, logger)
	_meta = MetaState.load_from()
	_meta_progress = MetaProgress.new(_db, _meta)
	if resume_state != null:
		# Resume: drive the loaded run (party/races/deck/level/position all persisted;
		# meta boons were already applied at the original start).
		_controller.run = resume_state
		run_seed = resume_state.seed
	else:
		if run_seed == 0:
			run_seed = randi()
		_controller.start_run(party, run_seed, party_races)
		# Act 1 uses the authored per-act map config (ADR-0019); fall back to the
		# generic defaults if the act curve is absent (partial content).
		var act1: ActConfig = _db.get_act(1)
		var map_cfg: MapGenConfig = act1.map if act1 != null and act1.map != null else MapGenConfig.new()
		_controller.run.map = MapGenerator.new().generate(map_cfg, run_seed)
		_meta_progress.apply_boons(_controller.run)  # banked cross-run boons (P3·08)
	# Open the run's telemetry file (interactive runs were previously unlogged —
	# only the headless harness wired a logger). RunController's combat_result /
	# event_choice / rest_choice / promotion events all flow into it from here on.
	var party_ids: Array[String] = []
	var hp_snapshot: Dictionary = {}
	for cid: StringName in _controller.run.party:
		party_ids.append(String(cid))
		hp_snapshot[String(cid)] = int(_controller.run.party_hp.get(cid, 0))
	_controller.telemetry.start_run({
		"party": party_ids,
		"seed": run_seed,
		"resumed": resume_state != null,
		"hp": hp_snapshot,
	})

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

	# The parchment sheet the map lives on (StS look).
	var sheet := ColorRect.new()
	sheet.color = COL_PARCHMENT
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 56
	sheet.offset_right = -56
	sheet.offset_top = 8
	sheet.offset_bottom = -8
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)

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
	title.add_theme_color_override("font_color", COL_INK)
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

	# Legend — "?" nodes are blind encounters revealed on arrival (ADR-0023).
	_legend_label = Label.new()
	_legend_label.add_theme_color_override("font_color", COL_DIM)
	root.add_child(_legend_label)

	# Scrollable map.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_map_box = MapSheet.new()
	_map_box.ink = COL_INK_DIM
	_map_box.add_theme_constant_override("separation", 26)
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
	if _legend_label != null:
		_legend_label.text = "Act %d   ·   Gold %d   ·   Legend: ? Unknown · Combat · Elite · Rest · Merchant · Treasure · BOSS" % [
			_controller.run.act, _controller.run.currency
		]
		# Sight relic (M3, reveal_boss): preview the act's boss on the header.
		if RelicEngine.reveals_boss(_run_relics()):
			var boss_name: String = _boss_preview_name()
			if boss_name != "":
				_legend_label.text += "   ·   Boss: %s" % boss_name
	var run: RunState = _controller.run
	for cid in run.party:
		var ch: CharacterData = PartyMember.character_for(_db, _controller.run, cid)
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
		var inspect := Button.new()
		inspect.text = "Inspect"
		inspect.custom_minimum_size = Vector2(84, 26)
		inspect.pressed.connect(_show_inspect.bind(cid, false))
		row.add_child(inspect)

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
	deck.text = "Skills: %d" % _controller.total_skills()
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


var _node_buttons: Dictionary = {}
var _legend_label: Label


func _refresh_map() -> void:
	_clear(_map_box)
	_node_buttons.clear()
	(_map_box as MapSheet).segments = []
	if _nav == null:
		return
	if _nav.is_complete():
		_status_label.text = "Run complete."
		return

	var reachable_ids: Dictionary = {}
	for n in _nav.reachable():
		reachable_ids[n.id] = true
	_status_label.text = "Choose your next stop." if not reachable_ids.is_empty() else "No path forward."

	# Group nodes by row. Render BOTTOM-UP (ADR-0023): the highest row (boss) is
	# drawn first so it sits at the top of the VBox, and row 0 (the start) is drawn
	# last so it sits at the bottom — the player climbs up the page, StS-style.
	var by_row: Dictionary = {}
	var graph: MapGraph = _nav.map()
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		var bucket: Array = by_row.get(node.row, [])
		bucket.append(node)
		by_row[node.row] = bucket
	var rows: Array = by_row.keys()
	rows.sort()
	rows.reverse()  # highest row (boss) first → top; row 0 last → bottom

	for row_v: Variant in rows:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 10)
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		var nodes: Array = by_row[row_v]
		nodes.sort_custom(func(a: MapNode, b: MapNode) -> bool: return String(a.id) < String(b.id))
		for node: MapNode in nodes:
			row_box.add_child(_node_button(node, reachable_ids.has(node.id)))
		_map_box.add_child(row_box)
	# Edges are drawn from button centers, which only exist after layout.
	call_deferred("_rebuild_edges")


## Compute dashed-edge segments (in the map sheet's local space) from each
## node's forward `next` links, once the buttons have a layout.
func _rebuild_edges() -> void:
	var sheet := _map_box as MapSheet
	if sheet == null or _nav == null:
		return
	var inv: Transform2D = sheet.get_global_transform().affine_inverse()
	var segs: Array = []
	var graph: MapGraph = _nav.map()
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		var from_btn: Button = _node_buttons.get(node.id, null)
		if from_btn == null or not is_instance_valid(from_btn):
			continue
		for next_id: StringName in node.next:
			var to_btn: Button = _node_buttons.get(next_id, null)
			if to_btn == null or not is_instance_valid(to_btn):
				continue
			var a: Vector2 = inv * from_btn.get_global_rect().get_center()
			var b: Vector2 = inv * to_btn.get_global_rect().get_center()
			# Trim so dashes start at the glyph edge, not its center.
			var dir: Vector2 = (b - a).normalized()
			segs.append([a + dir * 20.0, b - dir * 20.0])
	sheet.segments = segs
	sheet.queue_redraw()


func _node_button(node: MapNode, reachable: bool) -> Button:
	var cleared: bool = _controller.run.cleared.has(node.id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 52)
	# Selective fog (ADR-0023): a hidden, not-yet-cleared node reads as "?" — its
	# real type only shows once you've arrived (cleared) or a reveal sets hidden=false.
	# Sight relic (M3, reveal_map): a Cartographer's-Lens-style relic lifts the
	# fog for the whole map without mutating node state.
	var fogged: bool = node.hidden and not cleared \
			and not RelicEngine.reveals_map(_run_relics())
	btn.disabled = not reachable
	# StS look: icon-only nodes inked onto the parchment; the boss glyph is
	# larger; fogged nodes (ADR-0023) show the "?" glyph; missing art falls back
	# to a short text label.
	var glyph_id: StringName = node.node_type
	if fogged:
		glyph_id = UiAssets.MAP_GLYPH_UNKNOWN
	var glyph: Texture2D = UiAssets.map_glyph(glyph_id)
	var is_boss: bool = node.node_type == &"boss"
	btn.custom_minimum_size = Vector2(72, 64) if is_boss else Vector2(52, 46)
	if glyph != null:
		btn.icon = glyph
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 44 if is_boss else 26)
		btn.text = ""
	else:
		btn.text = "?" if fogged else TYPE_LABEL.get(node.node_type, String(node.node_type))
	# Ink colors: reachable = StS red, cleared = faded green check, rest = ink.
	var ink: Color = COL_INK
	if cleared:
		ink = COL_DONE
	elif reachable:
		ink = COL_REACH
	elif not reachable:
		ink = COL_INK_DIM if node.row > 0 else COL_INK
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color"]:
		btn.add_theme_color_override(state, ink)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		btn.add_theme_color_override(state, ink)
	# Flat (no panel) — the sheet is the surface; reachable nodes get a red ring.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(23)
	sb.set_content_margin_all(4)
	if reachable:
		sb.border_color = COL_REACH
		sb.set_border_width_all(2)
	if node.id == _controller.run.position:
		sb.border_color = COL_INK
		sb.set_border_width_all(2)
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	_node_buttons[node.id] = btn
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
		&"shop":
			_show_shop(node)
		&"treasure":
			_show_treasure(node)
		_:
			# Unknown node type: nothing to resolve, just clear and move on.
			_nav.complete_current()
			_refresh()


func _start_combat(node: MapNode) -> void:
	var enc_id: StringName = _nav.encounter_for(node)
	_active_battle = _controller.begin_combat(enc_id, _band_for(node.node_type)) if enc_id != &"" else null
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
	bv.telemetry = _controller.telemetry  # log card_played events into the run file
	bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bv.combat_finished.connect(_on_combat_finished.bind(bv))
	_open_overlay(bv)


func _on_combat_finished(outcome: int, bv: BattleView) -> void:
	# Settle HP/XP via the run layer, then advance or end the run.
	_controller.finish_combat(_active_encounter, _active_battle, bv.turns_taken())
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
		# Act cleared: record meta progress, then chain promotions + meta cash-out
		# before the victory screen.
		_meta_progress.record_act_cleared()
		_meta.save_to()
		_resolve_act_end()
	elif node.node_type == &"elite" or node.node_type == &"combat":
		_show_rewards_popup(node)
	else:
		_refresh()


## The run's owned relics resolved to RelicData — the list the M3 sight queries
## (reveal_map / reveal_boss) read each refresh.
func _run_relics() -> Array[RelicData]:
	var out: Array[RelicData] = []
	if _controller == null:
		return out
	for rid in _controller.run.relics:
		var relic: RelicData = _db.get_relic(rid)
		if relic != null:
			out.append(relic)
	return out


## The display name of this act's boss encounter (reveal_boss preview): finds the
## boss node and resolves it exactly the way travel would (RunNavigator's seeded
## pick), so the preview is always honest. "" when unresolvable.
func _boss_preview_name() -> String:
	if _nav == null:
		return ""
	var graph: MapGraph = _nav.map()
	if graph == null:
		return ""
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		if node.node_type != &"boss":
			continue
		var enc: EncounterData = _db.get_encounter(_nav.encounter_for(node))
		return enc.display_name if enc != null else ""
	return ""


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


# --- Rewards popup (after a won combat/elite — StS reference, 2026-06-10) ----

## Gold for clearing `node`, jittered ±25% deterministically per node.
func _gold_for(node: MapNode) -> int:
	var cfg: BattleConfig = _db.get_battle_config()
	var base: int = cfg.gold_per_elite if node.node_type == &"elite" else cfg.gold_per_combat
	if node.node_type == &"boss":
		base = cfg.gold_per_boss
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ hash(node.id)
	return maxi(1, base + rng.randi_range(-base / 4, base / 4))


## The StS-style "Rewards!" popup: take gold, take the card draft (and the relic
## on elites), or skip out.
func _show_rewards_popup(node: MapNode) -> void:
	var panel := _overlay_panel("Rewards!")
	var gold: int = _gold_for(node)

	var gold_btn := Button.new()
	gold_btn.custom_minimum_size = Vector2(360, 44)
	gold_btn.text = "%d Gold" % gold
	var gold_icon: Texture2D = UiAssets.map_glyph(&"treasure")
	if gold_icon != null:
		gold_btn.icon = gold_icon
		gold_btn.add_theme_constant_override("icon_max_width", 22)
	gold_btn.pressed.connect(func() -> void:
		_controller.run.currency += gold
		gold_btn.text = "Taken (+%d Gold)" % gold
		gold_btn.disabled = true
		_refresh_status())
	panel.add_child(gold_btn)

	if node.node_type == &"elite":
		var relic_btn := Button.new()
		relic_btn.custom_minimum_size = Vector2(360, 44)
		var pool: Array[StringName] = _controller.available_relics()
		if pool.is_empty():
			relic_btn.text = "Relic (none left)"
			relic_btn.disabled = true
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = run_seed ^ hash(_controller.run.cleared.size())
			var rid: StringName = pool[rng.randi_range(0, pool.size() - 1)]
			var relic: RelicData = _db.get_relic(rid)
			relic_btn.text = "Relic: %s" % (relic.display_name if relic != null else String(rid))
			var relic_icon: Texture2D = UiAssets.relic_icon(rid)
			if relic_icon != null:
				relic_btn.icon = relic_icon
				relic_btn.add_theme_constant_override("icon_max_width", 22)
			relic_btn.pressed.connect(func() -> void:
				if _controller.grant_relic(rid, "elite"):
					relic_btn.text = "Taken: %s" % (relic.display_name if relic != null else String(rid))
				relic_btn.disabled = true)
		panel.add_child(relic_btn)

	var card_btn := Button.new()
	card_btn.custom_minimum_size = Vector2(360, 44)
	card_btn.text = "Add a card to your deck"
	var card_icon: Texture2D = UiAssets.texture(UiAssets.UI_CARD_FRAME)
	if card_icon != null:
		card_btn.icon = card_icon
		card_btn.add_theme_constant_override("icon_max_width", 22)
	card_btn.pressed.connect(func() -> void:
		_close_overlay()
		_show_reward())
	panel.add_child(card_btn)

	var skip := Button.new()
	skip.text = "Skip Rewards"
	skip.custom_minimum_size = Vector2(160, 38)
	skip.pressed.connect(func() -> void:
		_close_overlay()
		_refresh())
	panel.add_child(skip)


# --- Card reward draft ("Choose a Card", StS reference) -----------------------

func _show_reward() -> void:
	var run: RunState = _controller.run
	# Depth-weighted rarities (ADR-0020): deeper acts draft B/C cards more often.
	var reward := CardReward.new(_db, CardReward.weights_for_act(run.act))
	var offer: Array[CardData] = reward.draft(run, CardReward.DEFAULT_CHOICES, run_seed + run.cleared.size())
	var panel := _overlay_panel("Choose a Card")
	if offer.is_empty():
		var none := Label.new()
		none.text = "No cards available."
		panel.add_child(none)
	# Three big cards side by side (StS reference): icon on top, name + cost +
	# effect text beneath.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	for card in offer:
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 230)
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icon: Texture2D = UiAssets.card_icon(card.id)
		if icon != null:
			b.icon = icon
			b.add_theme_constant_override("icon_max_width", 84)
		b.add_theme_font_size_override("font_size", 13)
		var owner_txt: String = "neutral" if card.character_tag == &"neutral" else String(card.character_tag)
		b.text = "%s  (%d)\n[%s · %s]\n%s" % [
			card.display_name, card.energy_cost, owner_txt, String(card.rarity), _card_summary(card)
		]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.20, 0.24, 0.30)
		sb.border_color = Color(0.45, 0.62, 0.80)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(10)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_on_reward_pick.bind(card.id))
		row.add_child(b)
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


## ADR-0022: the 1-of-2 archetype/specialization/capstone pick for one member.
func _show_tree_pick(cid: StringName, options: Array[Dictionary]) -> void:
	var member: CharacterData = PartyMember.character_for(_db, _controller.run, cid)
	var panel := _overlay_panel("%s — choose a path" % member.display_name)
	for node in options:
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 56)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		var bonus_v: Variant = node.get("stat_bonus", {})
		var bonus_bits: PackedStringArray = PackedStringArray()
		if bonus_v is Dictionary:
			for stat: Variant in bonus_v:
				bonus_bits.append("+%d %s" % [int(bonus_v[stat]), String(stat).to_upper()])
		var hook: String = String(node.get("hook", ""))
		b.text = "%s   (%s)%s" % [
			String(node.get("display_name", node.get("id"))), " · ".join(bonus_bits),
			"\n%s" % hook if hook != "" else "",
		]
		var nid := StringName(String(node.get("id")))
		b.pressed.connect(func() -> void:
			_controller.apply_progression(cid, nid)
			_close_overlay()
			_resolve_act_end())
		panel.add_child(b)


# --- Party inspect (owner, 2026-06-10): stats / skills / relics ---------------

## Full member sheet: effective stats (race base + class overlay + growth),
## skill collection vs active loadout (with derived-deck copy counts), and the
## party's relics with what each actually DOES. `editable` (rest nodes,
## ADR-0026) enables loadout toggling.
func _show_inspect(cid: StringName, editable: bool) -> void:
	var run: RunState = _controller.run
	var sheet: CharacterData = PartyMember.character_for(_db, run, cid)
	var race: RaceData = _db.get_race(StringName(String(run.party_races.get(cid, ""))))
	var alloc_v: Variant = run.allocated_stats.get(cid, {})
	var alloc: Dictionary = alloc_v if alloc_v is Dictionary else {}
	var s_str: int = sheet.strength + (race.str_mod if race != null else 0) + int(alloc.get(&"str", 0))
	var s_dex: int = sheet.dexterity + (race.dex_mod if race != null else 0) + int(alloc.get(&"dex", 0))
	var s_con: int = sheet.constitution + (race.con_mod if race != null else 0) + int(alloc.get(&"con", 0))
	var s_int: int = sheet.intelligence + (race.int_mod if race != null else 0) + int(alloc.get(&"int", 0))

	var panel := _overlay_panel(sheet.display_name)
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	var cls: StringName = PartyMember.class_of(run, cid)
	var atk: String = String(sheet.attack_stat).to_upper()
	head.text = "%s%s   ·   Level %d   ·   HP %d / %d\nSTR %d   DEX %d   CON %d   INT %d   ·   attacks with %s%s" % [
		race.display_name if race != null else "?",
		"" if cls == &"" or cls == cid else " " + String(cls).capitalize(),
		int(run.party_level.get(cid, 1)),
		int(run.party_hp.get(cid, 0)), PartyStats.effective_max_hp(_db, run, cid),
		s_str, s_dex, s_con, s_int, atk,
		"   ·   ASCENDED (+%.1f× on every card)" % sheet.ascension_mult if sheet.ascension_mult > 0.0 else "",
	]
	panel.add_child(head)

	# Skills: collection with active markers + copies contributed.
	var sk_label := Label.new()
	sk_label.add_theme_color_override("font_color", COL_DIM)
	var loadout: Array = run.active_loadouts.get(cid, [])
	sk_label.text = "Skills — %d in collection, %d / %d active%s:" % [
		(run.skill_collections.get(cid, []) as Array).size(), loadout.size(),
		_db.get_battle_config().skill_slots,
		"  (tap to toggle)" if editable else "  (editable at rest nodes)",
	]
	panel.add_child(sk_label)
	var grid := GridContainer.new()
	grid.columns = 2
	panel.add_child(grid)
	var coll: Array = run.skill_collections.get(cid, [])
	for i in range(coll.size()):
		var sid := StringName(String(coll[i]))
		var card: CardData = _db.get_card(sid)
		if card == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(290, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var active: bool = loadout.has(String(sid)) or loadout.has(sid)
		var copies: int = SkillLoadout.copies_for_rarity(card.rarity, _db.get_battle_config())
		b.text = "%s %s (%d) — %s, ×%d in deck" % [
			"●" if active else "○", card.display_name, card.energy_cost, String(card.rarity), copies,
		]
		var icon: Texture2D = UiAssets.card_icon(sid)
		if icon != null:
			b.icon = icon
			b.add_theme_constant_override("icon_max_width", 18)
		b.disabled = not editable
		if editable:
			b.pressed.connect(func() -> void:
				if active:
					(loadout as Array).erase(String(sid))
					(loadout as Array).erase(sid)
				elif loadout.size() < _db.get_battle_config().skill_slots:
					(loadout as Array).append(sid)
				_close_overlay()
				_show_inspect(cid, true))
		grid.add_child(b)

	# Relics: what each one actually does (trigger + effect + amount).
	var r_label := Label.new()
	r_label.add_theme_color_override("font_color", COL_DIM)
	r_label.text = "Relics (party-wide):" if not run.relics.is_empty() else "Relics: none yet."
	panel.add_child(r_label)
	for rid in run.relics:
		var relic: RelicData = _db.get_relic(rid)
		if relic == null:
			continue
		var rl := Label.new()
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD
		rl.text = "  %s — %s  [%s: %s %d]" % [
			relic.display_name, relic.description,
			String(relic.trigger), String(relic.effect), relic.amount,
		]
		panel.add_child(rl)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(110, 34)
	close.pressed.connect(func() -> void:
		_close_overlay()
		_refresh())
	panel.add_child(close)


# --- Act-2 recruit offer (ADR-0024) + Act-3 class pick (ADR-0021 pt2) ---------

## RNG 1-of-3 recruit offer, shown on arriving in Act 2 with a solo party. Each
## candidate is a whole person: race base line + origin kit + their own derived
## deck. Pure RNG, no re-rolls — adapting is the point.
func _show_recruit_offer() -> void:
	var panel := _overlay_panel("A stranger offers to join you")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	for rid in _controller.recruit_offer():
		var race: RaceData = _db.get_race(rid)
		if race == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 200)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icon: Texture2D = UiAssets.character_sprite(rid)
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 72)
		var custom: CardData = _db.get_card(race.custom_card)
		b.text = "%s\nSTR %d · DEX %d · CON %d · INT %d\nSignature: %s" % [
			race.display_name, race.str_mod, race.dex_mod, race.con_mod, race.int_mod,
			custom.display_name if custom != null else "—",
		]
		b.pressed.connect(func() -> void:
			var cid: StringName = _controller.recruit(rid)
			_status_label.text = "%s joins the party." % race.display_name if cid != &"" else "They wander off."
			_close_overlay()
			_refresh())
		row.add_child(b)


## The Act-3 class pick for one classless member (chained from _resolve_act_end
## until everyone is classed, then the act-end chain continues).
func _show_class_pick(cid: StringName) -> void:
	var member: CharacterData = PartyMember.character_for(_db, _controller.run, cid)
	var panel := _overlay_panel("%s — choose a class" % member.display_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	# ADR-0028: the class roster is db-driven — every CharacterData is a pickable
	# class line (fighter / rogue / mage + brawler / charmer), sorted for a stable order.
	var class_ids: Array = _db.characters.keys()
	class_ids.sort()
	for class_id: StringName in class_ids:
		var cls: CharacterData = _db.get_character(class_id)
		if cls == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 200)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icon: Texture2D = UiAssets.character_sprite(class_id)
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 72)
		b.text = "%s\n+%d STR · +%d DEX · +%d CON · +%d INT\nAttacks with %s\nUnlocks the %s card pool" % [
			cls.display_name, cls.strength, cls.dexterity, cls.constitution, cls.intelligence,
			String(cls.attack_stat).to_upper(), cls.display_name,
		]
		b.pressed.connect(func() -> void:
			_controller.choose_class(cid, class_id)
			_close_overlay()
			_resolve_act_end())  # next classless member, or carry on
		row.add_child(b)


# --- Shop / Treasure (ADR-0023: what Gold is for) -----------------------------

func _show_shop(node: MapNode) -> void:
	var shop := Shop.new(_db)
	var offer: Shop.ShopOffer = shop.build_offer(_controller.run, node.id)
	var panel := _overlay_panel("Merchant")

	var gold_lab := Label.new()
	gold_lab.add_theme_color_override("font_color", COL_ACCENT)
	gold_lab.text = "Gold: %d" % _controller.run.currency
	panel.add_child(gold_lab)

	# Three skills, big-card style with a price tag.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	for cid in offer.skill_ids:
		var card: CardData = _db.get_card(cid)
		if card == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(165, 215)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var icon: Texture2D = UiAssets.card_icon(card.id)
		if icon != null:
			b.icon = icon
			b.add_theme_constant_override("icon_max_width", 72)
		b.add_theme_font_size_override("font_size", 12)
		b.text = "%s  (%d)\n[%s]\n%s\n\n%d Gold" % [
			card.display_name, card.energy_cost, String(card.rarity),
			_card_summary(card), int(offer.prices.get(cid, 0)),
		]
		b.pressed.connect(func() -> void:
			if shop.buy_skill(_controller.run, offer, cid):
				b.text = "SOLD"
				b.disabled = true
				gold_lab.text = "Gold: %d" % _controller.run.currency
			else:
				gold_lab.text = "Gold: %d — not enough!" % _controller.run.currency)
		row.add_child(b)

	if offer.relic_id != &"":
		var relic: RelicData = _db.get_relic(offer.relic_id)
		var rb := Button.new()
		rb.custom_minimum_size = Vector2(360, 42)
		rb.text = "Relic: %s — %d Gold" % [
			relic.display_name if relic != null else String(offer.relic_id),
			int(offer.prices.get(offer.relic_id, 0)),
		]
		var ricon: Texture2D = UiAssets.relic_icon(offer.relic_id)
		if ricon != null:
			rb.icon = ricon
			rb.add_theme_constant_override("icon_max_width", 22)
		rb.pressed.connect(func() -> void:
			if shop.buy_relic(_controller.run, offer):
				rb.text = "SOLD"
				rb.disabled = true
				gold_lab.text = "Gold: %d" % _controller.run.currency
			else:
				gold_lab.text = "Gold: %d — not enough!" % _controller.run.currency)
		panel.add_child(rb)

	# Consumable item cards (ADR-0029): bought into the party inventory; they
	# ride the next fight's deck on top of the floor and exhaust+consume on play.
	for iid in offer.consumable_ids.duplicate():
		var item: CardData = _db.get_card(iid)
		if item == null:
			continue
		var ib := Button.new()
		ib.custom_minimum_size = Vector2(360, 42)
		ib.text = "Item: %s — %d Gold" % [item.display_name, int(offer.prices.get(iid, 0))]
		var iicon: Texture2D = UiAssets.card_icon(iid)
		if iicon != null:
			ib.icon = iicon
			ib.add_theme_constant_override("icon_max_width", 22)
		ib.pressed.connect(func() -> void:
			if shop.buy_consumable(_controller.run, offer, iid):
				ib.text = "SOLD"
				ib.disabled = true
				gold_lab.text = "Gold: %d" % _controller.run.currency
			else:
				gold_lab.text = "Gold: %d — not enough!" % _controller.run.currency)
		panel.add_child(ib)

	# "Remove a curse" service (ADR-0029): one button per carried curse; removal
	# restores an auto-fill basic in that member's derived deck.
	var removal_price: int = int(offer.prices.get(&"__curse_removal", 0))
	for cid_m in _controller.run.party:
		for curse_id in _controller.run.curses_of(cid_m).duplicate():
			var curse: CardData = _db.get_card(curse_id)
			var member_data: CharacterData = PartyMember.character_for(_db, _controller.run, cid_m)
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(360, 42)
			cb.text = "Remove curse: %s (%s) — %d Gold" % [
				curse.display_name if curse != null else String(curse_id),
				member_data.display_name if member_data != null else String(cid_m),
				removal_price,
			]
			cb.pressed.connect(func() -> void:
				if shop.buy_curse_removal(_controller.run, offer, cid_m, curse_id):
					cb.text = "Curse lifted."
					cb.disabled = true
					gold_lab.text = "Gold: %d" % _controller.run.currency
				else:
					gold_lab.text = "Gold: %d — not enough!" % _controller.run.currency)
			panel.add_child(cb)

	var hb := Button.new()
	hb.custom_minimum_size = Vector2(360, 42)
	hb.text = "Patch up the party (+%d HP each) — %d Gold" % [
		_db.get_battle_config().rest_heal, int(offer.prices.get(&"__heal", 0))
	]
	hb.pressed.connect(func() -> void:
		if shop.buy_heal(_controller.run, offer):
			hb.text = "Patched up."
			hb.disabled = true
			gold_lab.text = "Gold: %d" % _controller.run.currency
			_refresh_status()
		else:
			gold_lab.text = "Gold: %d — not enough!" % _controller.run.currency)
	panel.add_child(hb)

	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(120, 36)
	leave.pressed.connect(func() -> void:
		_nav.complete_current()
		_close_overlay()
		_refresh())
	panel.add_child(leave)


func _show_treasure(node: MapNode) -> void:
	var shop := Shop.new(_db)
	var loot: Dictionary = shop.treasure_roll(_controller.run, node.id)
	var panel := _overlay_panel("Treasure!")
	var what := Label.new()
	what.add_theme_font_size_override("font_size", 16)
	match loot.get("kind"):
		&"relic":
			var relic: RelicData = _db.get_relic(loot.get("id", &""))
			what.text = "You find a relic: %s" % (relic.display_name if relic != null else "?")
		&"skill":
			var card: CardData = _db.get_card(loot.get("id", &""))
			what.text = "You find a technique: %s" % (card.display_name if card != null else "?")
		&"consumable":
			var item: CardData = _db.get_card(loot.get("id", &""))
			what.text = "You find an item: %s" % (item.display_name if item != null else "?")
		_:
			what.text = "You find %d Gold" % int(loot.get("amount", 0))
	panel.add_child(what)
	var take := Button.new()
	take.text = "Take it"
	take.custom_minimum_size = Vector2(160, 40)
	take.pressed.connect(func() -> void:
		var got: String = shop.take_treasure(_controller.run, loot)
		_status_label.text = "Treasure: %s" % got
		_nav.complete_current()
		_close_overlay()
		_refresh())
	panel.add_child(take)


# --- Rest -------------------------------------------------------------------

func _show_rest(node: MapNode) -> void:
	var panel := _overlay_panel("Rest")
	var heal := Button.new()
	heal.custom_minimum_size = Vector2(360, 38)
	heal.text = "Heal the party (+%d HP each)" % _db.get_battle_config().rest_heal
	heal.pressed.connect(_on_rest_heal)
	panel.add_child(heal)

	for cid in _controller.run.party:
		var member: CharacterData = PartyMember.character_for(_db, _controller.run, cid)
		var manage := Button.new()
		manage.custom_minimum_size = Vector2(360, 34)
		manage.text = "Manage %s's skills (loadout)" % member.display_name
		manage.pressed.connect(_show_inspect.bind(cid, true))
		panel.add_child(manage)

	var up_label := Label.new()
	up_label.add_theme_color_override("font_color", COL_DIM)
	up_label.text = "…or upgrade a card:"
	panel.add_child(up_label)

	var any: bool = false
	var seen: Dictionary = {}
	var all_skills: Array[StringName] = []
	for cid in _controller.run.party:
		all_skills.append_array(_controller.collection_of(cid))
	for card_id in all_skills:
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
		# M3: flavor-gated choices (race/class/min_gold/has_curse) are HIDDEN
		# when unmet — the resolver rejects them too; this is just presentation.
		if not EventResolver.is_choice_available(_controller.run, choice):
			continue
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

# --- Class promotion at the act boundary (P3·06) ----------------------------

## Act-boundary chain: offer each eligible promotion (pick 1 of 2), then a meta
## cash-out boon if one is available, then the victory screen. Each choice re-enters
## here so steps resolve one at a time. (Promotions are dormant until a member hits
## the promotion level; cash-out until enough acts are cleared.)
func _resolve_act_end() -> void:
	# ADR-0021 pt2: the end of Act 3 is the CLASS PICK — every classless member
	# chooses Fighter / Rogue / Mage before the descent to Act 4.
	if _controller.run.act >= 3:
		for cid in _controller.run.party:
			if _controller.is_classless(cid):
				_show_class_pick(cid)
				return
	# ADR-0022: 1-of-2 tree picks at the Act 6/9/12 boundaries, then Ascension at 15.
	for cid in _controller.run.party:
		var options: Array[Dictionary] = _controller.progression_options(cid)
		if not options.is_empty():
			_show_tree_pick(cid, options)
			return
	for cid in _controller.run.party:
		if _controller.ascension_available(cid):
			_controller.ascend(cid)
			var member: CharacterData = PartyMember.character_for(_db, _controller.run, cid)
			_status_label.text = "%s ASCENDS — every card grows stronger, and an Ult joins their skills." % member.display_name
			_resolve_act_end()
			return
	if _meta_progress != null and _meta_progress.cash_out_available():
		_show_cashout()
		return
	_advance_act_or_victory()


## ADR-0019: the act's boss is down — move to the next authored act (new map,
## same party/HP/deck/relics/levels), or end the run in victory when the final
## authored act has fallen.
func _advance_act_or_victory() -> void:
	if not _controller.advance_act():
		_show_run_end(true)
		return
	_nav = RunNavigator.new(_db, _controller.run)
	_status_label.text = "Act %d — the descent continues. Choose your next stop." % _controller.run.act
	# ADR-0028: announce the Sponsor Box the cleared act's Fame just bought.
	if _controller.last_sponsor_relic != &"":
		var sponsor: RelicData = _db.get_relic(_controller.last_sponsor_relic)
		if sponsor != null:
			_status_label.text += "\nSPONSOR BOX — your fame earned: %s (%s)" % [sponsor.display_name, sponsor.description]
	_refresh()
	# ADR-0024: arriving in Act 2 with a solo party triggers the recruit offer.
	if _controller.run.act == 2 and _controller.run.party.size() < 2:
		_show_recruit_offer()


## Node type -> enemy level band (ADR-0019) for combat scaling.
func _band_for(node_type: StringName) -> StringName:
	match node_type:
		&"elite":
			return &"elite"
		&"boss":
			return &"boss"
		_:
			return &"trash"


## Cross-run cash-out (P3·08): pick one banked boon for future runs.
func _show_cashout() -> void:
	var panel := _overlay_panel("Exit package — bank a boon for future runs")
	for boon in _meta_progress.boon_choices():
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 40)
		b.text = "%s — %s" % [boon.display_name, boon.description]
		b.pressed.connect(_on_cashout_pick.bind(boon.id))
		panel.add_child(b)


func _on_cashout_pick(boon_id: StringName) -> void:
	_meta_progress.cash_out(boon_id)
	_meta.save_to()
	_close_overlay()
	_resolve_act_end()


func _show_promotion(cid: StringName, branches: Array[PromotionData]) -> void:
	var ch: CharacterData = _db.get_character(cid)
	var who: String = ch.display_name if ch != null else String(cid)
	var panel := _overlay_panel("%s may promote — choose a path" % who)
	for promo in branches:
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 40)
		var bits: Array[String] = []
		for pair in [["STR", promo.str_mod], ["DEX", promo.dex_mod], ["CON", promo.con_mod], ["INT", promo.int_mod]]:
			if int(pair[1]) != 0:
				bits.append("+%d %s" % [int(pair[1]), pair[0]])
		b.text = "%s  (%s, card: %s)" % [promo.display_name, ", ".join(bits), promo.signature_card]
		b.pressed.connect(_on_promotion_pick.bind(cid, promo.id))
		panel.add_child(b)


func _on_promotion_pick(cid: StringName, promotion_id: StringName) -> void:
	_controller.apply_promotion(cid, promotion_id)
	_close_overlay()
	_resolve_act_end()  # next eligible member, then cash-out, then run end


func _show_run_end(victory: bool) -> void:
	# Close out the telemetry run (writes run_end + a runs_summary.jsonl line).
	# Safe if the logger is already inactive (end_run no-ops).
	var ended: RunState = _controller.run
	var hp_left: int = 0
	for cid: StringName in ended.party:
		hp_left += int(ended.party_hp.get(cid, 0))
	_controller.telemetry.end_run({
		"outcome": "WIN" if victory else "LOSS",
		"nodes_cleared": ended.cleared.size(),
		"party_hp_remaining": hp_left,
		"skills_total": _controller.total_skills(),
	})
	_clear_save()  # the run is over — don't offer to resume it
	var panel := _overlay_panel("VICTORY — the act is cleared!" if victory else "DEFEAT — the party fell.")
	var summary := Label.new()
	summary.add_theme_color_override("font_color", COL_DIM)
	var run: RunState = _controller.run
	summary.text = "Nodes cleared: %d   |   Skills: %d" % [run.cleared.size(), _controller.total_skills()]
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
