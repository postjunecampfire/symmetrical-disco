extends "res://addons/gut/test.gd"
## UiAssets / SfxPlayer (P2·13 asset pass). The contract under test is the
## GRACEFUL-FALLBACK guarantee: every lookup for content with no art/audio file
## returns null (or false), never errors — so views stay functional and the
## headless suite never depends on imported assets. Positive loads (real
## textures/streams) are deliberately NOT asserted here: they require the Godot
## importer to have run, which the headless gate does not guarantee.

const NO_SUCH_ID: StringName = &"no_such_content_id_xyz"


func test_missing_assets_resolve_to_null() -> void:
	assert_null(UiAssets.enemy_sprite(NO_SUCH_ID), "missing enemy sprite -> null")
	assert_null(UiAssets.character_sprite(NO_SUCH_ID), "missing character sprite -> null")
	assert_null(UiAssets.card_icon(NO_SUCH_ID), "missing card icon -> null")
	assert_null(UiAssets.status_icon(NO_SUCH_ID), "missing status icon -> null")
	assert_null(UiAssets.relic_icon(NO_SUCH_ID), "missing relic icon -> null")
	assert_null(UiAssets.map_glyph(NO_SUCH_ID), "missing map glyph -> null")
	assert_null(UiAssets.sfx(NO_SUCH_ID), "missing sfx -> null")
	assert_null(UiAssets.music(NO_SUCH_ID), "missing music -> null")


func test_texture_and_audio_guard_bad_paths() -> void:
	assert_null(UiAssets.texture("res://assets/nope/missing.png"), "missing texture path -> null")
	assert_null(UiAssets.audio("res://assets/nope/missing.ogg"), "missing audio path -> null")


func test_unit_sprite_handles_null_and_sourceless_units() -> void:
	assert_null(UiAssets.unit_sprite(null), "null unit -> null")
	var unit := Combatant.new()
	assert_null(UiAssets.unit_sprite(unit), "unit without source_data -> null")


func test_sfx_player_is_silent_when_asset_missing() -> void:
	var sfx := SfxPlayer.new()
	add_child_autofree(sfx)  # triggers _ready (builds the pool)
	assert_false(sfx.play(NO_SUCH_ID), "missing sfx -> no-op, returns false")
