class_name SfxPlayer
extends Node
## Fire-and-forget sound effects for the views. A small round-robin pool of
## AudioStreamPlayers so overlapping cues (e.g. card play + hit) don't cut each
## other off. Streams resolve by name through UiAssets.sfx() — a missing file is
## a silent no-op, so the views (and the headless test suite) never depend on
## audio assets being present or imported.

const POOL_SIZE: int = 4

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for _i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


## Play `assets/audio/sfx/<sfx_name>.ogg` if it exists. Returns true if a stream
## was started, false if the asset is absent (silent fallback).
func play(sfx_name: StringName) -> bool:
	var stream: AudioStream = UiAssets.sfx(sfx_name)
	if stream == null or _players.is_empty():
		return false
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()
	return true
