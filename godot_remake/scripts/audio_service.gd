extends Node

const SOUND_PATHS := {
	"hover_item":"res://assets/extracted/sounds/sound_0001.mp3",
	"hover_npc":"res://assets/extracted/sounds/sound_0002.mp3",
	"summon_pet":"res://assets/extracted/sounds/sound_0003.mp3",
	"learn_skill":"res://assets/extracted/sounds/sound_0004.mp3",
	"select_npc":"res://assets/extracted/sounds/sound_0005.mp3",
	"send_flower":"res://assets/extracted/sounds/sound_0006.mp3",
	"level_up":"res://assets/extracted/sounds/sound_0007.mp3",
	"change_map":"res://assets/extracted/sounds/sound_0008.mp3",
	"refine_fail":"res://assets/extracted/sounds/sound_0010.mp3",
	"refine_success":"res://assets/extracted/sounds/sound_0011.mp3",
	"boss":"res://assets/extracted/sounds/sound_0012.mp3",
	"potion":"res://assets/extracted/sounds/sound_0013.mp3",
	"attack":"res://assets/extracted/sounds/sound_0014.mp3",
	"victory":"res://assets/extracted/sounds/sound_0015.mp3",
	"open":"res://assets/extracted/sounds/sound_0016.mp3",
	"npc_dialogue":"res://assets/extracted/sounds/sound_0017.mp3",
	"death":"res://assets/extracted/sounds/sound_0018.mp3",
	"equip":"res://assets/extracted/sounds/sound_0020.mp3",
	# v1.37：SWF StartSound 证据驱动的战斗声音（sound_0123/0132/0518/0520，
	# 证据见 docs/evidence/combat_feedback_v103_v9.txt 与 docs/combat_feedback_registry.json）。
	"monster_attack_normal":"res://assets/extracted/sounds/sound_0123.mp3",
	"monster_attack_boss":"res://assets/extracted/sounds/sound_0132.mp3",
	"skill_flying_slash":"res://assets/extracted/sounds/sound_0518.mp3",
	"skill_star_sword":"res://assets/extracted/sounds/sound_0520.mp3",
}

const PLAY_HISTORY_LIMIT := 512

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var _play_history: Array[Dictionary] = []  # 有界历史：{sound_name, index}（v1.37 整改01）
var _play_counts: Dictionary = {}  # sound_name -> 请求次数


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -14.0
	add_child(music_player)
	var music: Resource = load("res://assets/extracted/sounds/sound_0019.mp3")
	if music is AudioStreamMP3:
		music.loop = true
	music_player.stream = music
	music_player.play()
	for index in 4:
		var player := AudioStreamPlayer.new()
		player.volume_db = -5.0
		add_child(player)
		sfx_players.append(player)


## v1.37 整改01：真实 AudioService 事件记录——headless 下先记录事件/请求再跳过实际播放器；
## 非 headless 下记录同一事件后再播放声音。兼容入口保留（生产反馈经 FeedbackService.emit
## 调用本函数；直接调用本函数的声音也全部记录，可被测试独立验证）。
func play(sound_name: String) -> void:
	_play_history.append({"sound_name": sound_name, "index": _play_history.size() + 1})
	if _play_history.size() > PLAY_HISTORY_LIMIT:
		_play_history.remove_at(0)
	_play_counts[sound_name] = int(_play_counts.get(sound_name, 0)) + 1
	if sfx_players.is_empty():
		return
	var path := str(SOUND_PATHS.get(sound_name, ""))
	if path.is_empty():
		return
	var player: AudioStreamPlayer = sfx_players[0]
	for candidate: AudioStreamPlayer in sfx_players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = load(path)
	player.play()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


# --- 测试钩子（只读历史/计数与清理；不参与生产路径）---

## 播放历史副本（只读用途）：{sound_name, index}（含 headless 下的记录）。
func test_play_history() -> Array:
	return _play_history.duplicate(true)


## 指定声音的请求次数（headless 下同样计数）。
func test_play_count(sound_name: String) -> int:
	return int(_play_counts.get(sound_name, 0))


## 播放历史条数。
func test_play_history_size() -> int:
	return _play_history.size()


## 测试清理（生产不调用）。
func test_reset_play_history() -> void:
	_play_history.clear()
	_play_counts.clear()
