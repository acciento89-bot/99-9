extends Node
# One owner per main scene. Precomputed original PCM; no work on the timing path.
signal settings_changed
var settings_path := "user://audio-v1.cfg"
var music_enabled := true
var sound_enabled := true
var save_error := false
var music_player: AudioStreamPlayer
var ui_player: AudioStreamPlayer
var result_player: AudioStreamPlayer
var hit_stream: AudioStreamWAV
var miss_stream: AudioStreamWAV
var _music_fade: Tween
var _sound_fade: Tween
var _focused := true
var _resumed := true
const MUSIC_DB := -20.0
const SOUND_DB := -12.0
const FADE_SECONDS := .06

func _ready() -> void:
    var config := ConfigFile.new()
    if config.load(settings_path) == OK:
        var music: Variant = config.get_value("audio", "music", true)
        var sound: Variant = config.get_value("audio", "sound", true)
        # Corrupt/unexpected values never become truthy strings.
        if music is bool: music_enabled = music
        if sound is bool: sound_enabled = sound
    music_player = _player("Music", "precision-loop.wav", MUSIC_DB)
    music_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    music_player.stream.loop_begin = 0
    music_player.stream.loop_end = 24 * 22050
    ui_player = _player("UI", "ui.wav", SOUND_DB)
    result_player = _player("Outcome", "hit.wav", SOUND_DB)
    hit_stream = result_player.stream
    miss_stream = _wav("miss.wav")
    _sync_music()

func _wav(filename: String) -> AudioStreamWAV:
    var path := "res://assets/audio/" + filename
    # Android explicitly includes original WAVs. Other existing all-resource
    # presets may remap imported WAVs; support that without altering iOS presets.
    if FileAccess.file_exists(path): return AudioStreamWAV.load_from_file(path)
    return load(path) as AudioStreamWAV

func _player(label: String, filename: String, gain: float) -> AudioStreamPlayer:
    var player := AudioStreamPlayer.new()
    player.name = label
    player.max_polyphony = 1
    player.volume_db = gain
    player.stream = _wav(filename)
    add_child(player)
    return player

func _save_preferences() -> bool:
    var config := ConfigFile.new()
    config.set_value("audio", "music", music_enabled)
    config.set_value("audio", "sound", sound_enabled)
    save_error = config.save(settings_path) != OK
    return not save_error

func set_music_enabled(enabled: bool) -> void:
    var previous := music_enabled
    music_enabled = enabled
    if not _save_preferences(): music_enabled = previous
    _sync_music()
    settings_changed.emit()

func set_sound_enabled(enabled: bool) -> void:
    var previous := sound_enabled
    sound_enabled = enabled
    if not _save_preferences(): sound_enabled = previous
    if _sound_fade != null: _sound_fade.kill()
    if not sound_enabled:
        _sound_fade = create_tween().set_parallel(true)
        for player in [ui_player, result_player]:
            _sound_fade.tween_property(player, "volume_db", -80.0, FADE_SECONDS)
        _sound_fade.chain().tween_callback(_stop_effects)
    else:
        for player in [ui_player, result_player]: player.volume_db = SOUND_DB
    settings_changed.emit()

func _stop_effects() -> void:
    ui_player.stop()
    result_player.stop()

func _sync_music() -> void:
    if music_player == null: return
    if _music_fade != null: _music_fade.kill()
    if not _focused or not _resumed:
        music_player.stream_paused = true
        _stop_effects()
        return
    music_player.stream_paused = false
    _music_fade = create_tween()
    if music_enabled:
        if not music_player.playing:
            music_player.volume_db = -80.0
            music_player.play()
        _music_fade.tween_property(music_player, "volume_db", MUSIC_DB, FADE_SECONDS)
    else:
        _music_fade.tween_property(music_player, "volume_db", -80.0, FADE_SECONDS)
        _music_fade.tween_callback(music_player.stop)

func play_ui() -> void:
    if sound_enabled and _focused and _resumed and not ui_player.playing:
        ui_player.play()

func play_result(hit: bool) -> void:
    if sound_enabled and _focused and _resumed and not result_player.playing:
        result_player.stream = hit_stream if hit else miss_stream
        result_player.play()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _focused = false
    elif what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true
    elif what == NOTIFICATION_APPLICATION_PAUSED: _resumed = false
    elif what == NOTIFICATION_APPLICATION_RESUMED: _resumed = true
    else: return
    _sync_music()

func _exit_tree() -> void:
    if _music_fade != null: _music_fade.kill()
    if _sound_fade != null: _sound_fade.kill()
    if music_player != null: music_player.stop()
    if ui_player != null: ui_player.stop()
    if result_player != null: result_player.stop()
