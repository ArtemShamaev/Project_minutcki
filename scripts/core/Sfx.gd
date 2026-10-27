class_name Sfx
## Tiny sound-effect player with a pool of AudioStreamPlayers.

const MAP := {
	"click": "click_002", "place": "impactWood_heavy_001", "road": "impactPlate_medium_000",
	"bulldoze": "impactMining_002", "zone": "drop_002", "error": "error_004",
	"milestone": "confirmation_002", "open": "maximize_003", "bad": "bong_001", "toggle": "switch_002",
}
static var _players: Array = []
static var _streams := {}
static var _i := 0
static var enabled := true


static func init(parent: Node) -> void:
	_players.clear()
	for i in 8:
		var p := AudioStreamPlayer.new()
		parent.add_child(p)
		_players.append(p)


static func play(name: String, vol_db: float = -4.0) -> void:
	if not enabled or _players.is_empty() or not MAP.has(name):
		return
	if not _streams.has(name):
		_streams[name] = load("res://assets/sfx/%s.ogg" % MAP[name])
	var p: AudioStreamPlayer = _players[_i % _players.size()]
	_i += 1
	p.stream = _streams[name]
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()
