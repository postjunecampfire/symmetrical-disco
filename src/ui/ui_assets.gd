class_name UiAssets
extends RefCounted
## Centralised, GUARDED lookup for optional view assets (sprites / icons / audio),
## resolved by GAME ID — convention over data: the asset for content id X lives at
## a fixed path named X (assets/sprites/enemies/ogre.png ↔ data/enemies/ogre.json),
## so adding art for new content is "drop a file", no schema or loader change.
##
## Every lookup degrades gracefully: a missing (or unimported) file returns null
## and the views keep their text-only form. This keeps the headless GUT suite and
## the attrition harness independent of imported art.
##
## Sources (see CREDITS.md): DCSS tiles (CC0), game-icons.net (CC BY 3.0),
## Kenney packs (CC0), OpenGameArt CC0 music.

const SPRITE_ENEMY_DIR := "res://assets/sprites/enemies/"
const SPRITE_CHARACTER_DIR := "res://assets/sprites/characters/"
const ICON_CARD_DIR := "res://assets/icons/cards/"
const ICON_STATUS_DIR := "res://assets/icons/status/"
const ICON_RELIC_DIR := "res://assets/icons/relics/"
const ICON_MAP_DIR := "res://assets/icons/map/"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const UI_CARD_FRAME := "res://assets/ui/card_frame.png"

## The map glyph used for a hidden, not-yet-cleared node (ADR-0023 fog).
const MAP_GLYPH_UNKNOWN: StringName = &"unknown"


## Load a texture, or null if the file is absent/unimported. Never errors.
static func texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D


## Load an audio stream, or null if the file is absent/unimported. Never errors.
static func audio(path: String) -> AudioStream:
	if not ResourceLoader.exists(path, "AudioStream"):
		return null
	return load(path) as AudioStream


static func enemy_sprite(enemy_id: StringName) -> Texture2D:
	return texture(SPRITE_ENEMY_DIR + String(enemy_id) + ".png")


static func character_sprite(character_id: StringName) -> Texture2D:
	return texture(SPRITE_CHARACTER_DIR + String(character_id) + ".png")


## Resolve the sprite for any combatant from its source data (CharacterData for
## players, EnemyData for foes). Null when no art exists for that id.
static func unit_sprite(unit: Combatant) -> Texture2D:
	if unit == null or unit.source_data == null:
		return null
	var character := unit.source_data as CharacterData
	if character != null:
		var tex: Texture2D = character_sprite(character.id)
		if tex == null:
			# Synthesized members (ADR-0024): tags carry class then race ids.
			for tag in character.tags:
				tex = character_sprite(tag)
				if tex != null:
					break
		return tex
	var enemy := unit.source_data as EnemyData
	if enemy != null:
		return enemy_sprite(enemy.id)
	return null


static func card_icon(card_id: StringName) -> Texture2D:
	return texture(ICON_CARD_DIR + String(card_id) + ".png")


static func status_icon(status_id: StringName) -> Texture2D:
	return texture(ICON_STATUS_DIR + String(status_id) + ".png")


static func relic_icon(relic_id: StringName) -> Texture2D:
	return texture(ICON_RELIC_DIR + String(relic_id) + ".png")


## Glyph for a map node type (combat/elite/boss/rest/event/shop/treasure), or the
## "?" unknown glyph for fogged nodes (pass MAP_GLYPH_UNKNOWN).
static func map_glyph(node_type: StringName) -> Texture2D:
	return texture(ICON_MAP_DIR + String(node_type) + ".png")


static func sfx(sfx_name: StringName) -> AudioStream:
	return audio(SFX_DIR + String(sfx_name) + ".ogg")


static func music(track_name: StringName) -> AudioStream:
	return audio(MUSIC_DIR + String(track_name) + ".mp3")
