extends SceneTree
const Audio = preload("res://scripts/audio_service.gd")
const Practice = preload("res://scripts/practice_model.gd")
const Archive = preload("res://scripts/practice_archive.gd")
const Captions = preload("res://scripts/ranking_captions.gd")
class Probe extends "res://scripts/main_audio.gd":
    var path: String
    var caption_platform := "Android"
    var pause_calls := 0
    func _practice_pause() -> void:
        pause_calls += 1
        super._practice_pause()
    func _ranking_platform() -> String: return caption_platform
    func _audio_settings_path() -> String: return path + ".cfg"
    func _practice_archive_path() -> String: return path + ".practice.json"
    func _practice_now() -> int: return 1000000
    func _load_save() -> void: player_id = "audio-qa"
    func _save() -> void: pass
class Rankings extends Node:
    signal leaderboard_loaded(mode: String, top: Array, me: Variant)
    signal leaderboard_failed(message: String)
    signal score_submitted(player: Dictionary)
    signal score_submit_failed(message: String)
    signal name_saved(player: Dictionary)
    signal name_save_failed(message: String)
    func submit_score(_a: String, _b: int, _c: String, _d: String) -> void: pass
class Billing extends Node:
    signal store_state_changed(ready: bool, message: String)
    signal products_updated(prices: Dictionary)
    signal entitlements_updated(theme_ids: Array[String])
    signal purchase_completed(theme_id: String)
    signal purchase_failed(message: String)
    signal restore_completed(theme_ids: Array[String])
    signal restore_failed(message: String)
    signal remove_ads_product_updated(price: String)
    signal remove_ads_entitlement_updated(owned: bool)
    signal remove_ads_purchase_completed
    func start_store() -> void: pass
    func get_display_price(_id: String) -> String: return ""
class Ads extends Node:
    signal interstitial_closed
    signal ad_error(message: String)
    func start_ads() -> void: pass
    func set_ads_removed(_owned: bool) -> void: pass
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("FAIL " + message)
func _initialize() -> void: call_deferred("run_checks")
func wait_effect(player: AudioStreamPlayer) -> void:
    var deadline := Time.get_ticks_msec() + 2500
    while player.playing and Time.get_ticks_msec() < deadline:
        await process_frame
    check(not player.playing, "one-shot naturally completes within a bounded deadline")
func make_app(path: String, platform: String = "Android") -> Probe:
    var app := Probe.new()
    app.path = path
    app.caption_platform = platform
    for entry in [[Rankings.new(), "LeaderboardService"], [Billing.new(), "IapService"], [Ads.new(), "AdsService"]]:
        entry[0].name = entry[1]
        app.add_child(entry[0])
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(app)
    return app
func has_caption(node: Node, text: String) -> bool:
    if node is Label and node.text == text: return true
    for child in node.get_children():
        if has_caption(child, text): return true
    return false
func run_checks() -> void:
    root.size = Vector2i(1080, 1920)
    var folder: String = OS.get_cmdline_user_args()[0]
    # Actual exported-resource remapping, without running an Editor importer.
    var raw := AudioStreamWAV.load_from_file("res://assets/audio/ui.wav")
    check(ResourceSaver.save(raw, "res://assets/audio/remapped-test.tres") == OK, "temporary remapped WAV fixture saves")
    var remap := FileAccess.open("res://assets/audio/remapped-test.wav.remap", FileAccess.WRITE)
    remap.store_string('[remap]\npath="res://assets/audio/remapped-test.tres"\n')
    remap.close()
    var loader = Audio.new()
    var imported: AudioStreamWAV = loader._wav("remapped-test.wav")
    check(imported != null and imported.data == raw.data, "actual loader handles exported WAV remapping with identical PCM")
    loader.free()
    check(Captions.menu("iOS") == "GLOBAL RANKINGS" and Captions.ranking("iOS") == "GLOBAL RANKINGS", "iOS formatter never names another platform")
    check(Captions.menu("Android") == "GLOBAL RANKINGS · iOS + ANDROID" and Captions.ranking("Android") == "GLOBAL · iOS + ANDROID", "Android retains legitimate cross-platform ranking captions")
    var ios := make_app(folder.path_join("caption-ios"), "iOS")
    await process_frame
    check(has_caption(ios.menu_layer, "GLOBAL RANKINGS") and has_caption(ios.leaderboard_layer, "GLOBAL RANKINGS"), "both actual iOS UI captions use the formatter")
    check(not has_caption(ios.menu_layer, "GLOBAL RANKINGS · iOS + ANDROID") and not has_caption(ios.leaderboard_layer, "GLOBAL · iOS + ANDROID"), "actual iOS menu and ranking do not expose cross-platform captions")
    ios.queue_free()
    await process_frame
    var app := make_app(folder.path_join("prefs"))
    await process_frame
    app.set_process(false)
    var audio = app._audio
    check(has_caption(app.menu_layer, "GLOBAL RANKINGS · iOS + ANDROID") and has_caption(app.leaderboard_layer, "GLOBAL · iOS + ANDROID"), "actual Android UI preserves original wording")
    check(audio.music_enabled and audio.sound_enabled, "both independent preferences default on")
    check(audio.get_child_count() == 3 and audio.music_player.playing, "one music owner with exactly three bounded players")
    check(audio.music_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "actual WAV stream loops")
    check(audio.music_player.stream.loop_end == 24 * 22050 - 1, "last valid frame of the original24s audio")
    check(audio.music_player.volume_db <= -18.0, "quiet default music gain")
    app._open_settings()
    await process_frame
    check(app._audio_music_button.is_visible_in_tree() and app._audio_sound_button.is_visible_in_tree(), "audio controls live in actual normal Settings")
    # Actual viewport touch delivery, not a direct setter or pressed signal.
    var event := InputEventScreenTouch.new()
    event.index = 0; event.position = app._audio_music_button.get_global_rect().get_center(); event.pressed = true
    root.push_input(event, true)
    var release := InputEventScreenTouch.new()
    release.index = 0; release.position = event.position; release.pressed = false
    root.push_input(release, true)
    await create_timer(.15).timeout
    check(not audio.music_enabled and audio.sound_enabled and not audio.music_player.playing, "actual Settings touch independently disables and fades music")
    app._audio_sound_button.pressed.emit()
    check(not audio.sound_enabled and app._audio_sound_button.text == "SOUND: OFF", "sound control has truthful state")
    var cold := make_app(folder.path_join("prefs"))
    await process_frame
    cold.set_process(false)
    check(not cold._audio.music_enabled and not cold._audio.sound_enabled and not cold._audio.music_player.playing, "cold start reads both saved switches")
    cold.queue_free()
    await process_frame
    audio.settings_path = folder.path_join("missing/subdir/settings.cfg")
    app._audio_music_button.pressed.emit()
    check(not audio.music_enabled and app._audio_status.text.contains("NOT SAVED"), "failed preference write rolls back and exposes failure")
    audio.settings_path = folder.path_join("prefs.cfg")
    audio.set_music_enabled(true); audio.set_sound_enabled(true)
    await create_timer(.15).timeout
    audio.play_ui()
    check(audio.ui_player.playing, "normal enabled UI effect uses actual stream")
    audio.set_sound_enabled(false)
    await create_timer(.12).timeout
    audio.play_result(true)
    check(not audio.ui_player.playing and not audio.result_player.playing, "muted effects cannot start and existing effect fades out")
    audio.set_sound_enabled(true)
    app._start_game_session(); app._start_round(); app._process(.1)
    var held := app.meter_phase
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    app._process(30.0)
    check(app.game_paused and app.meter_phase == held, "focus loss holds Classic exact phase")
    check(audio.music_player.stream_paused and not audio.result_player.playing, "focus loss pauses music and discards effects")
    for repeat in range(4):
        app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
        app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    await create_timer(.15).timeout
    app._process(20.0)
    check(app.game_paused and app.meter_phase == held, "music foreground resume never resumes Classic timing")
    check(audio.get_child_count() == 3 and audio.music_player.playing and not audio.music_player.stream_paused, "repeated lifecycle events cannot duplicate players")
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
    check(audio.music_player.stream_paused, "resume without focus cannot expose background audio")
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    app._resume_game(); app.meter_value = 99.95; app._stop_round()
    check(audio.result_player.stream == audio.hit_stream, "real Classic streak hit selects hit effect")
    await wait_effect(audio.result_player)
    app._start_round(); app.meter_value = 50.0; app._stop_round()
    check(audio.result_player.stream == audio.miss_stream, "real Classic miss selects miss effect")
    await wait_effect(audio.result_player)
    app._return_to_menu(); app._practice_open_menu(); app._practice_begin(1); app._practice_action()
    app._practice_round = Practice.tick(app._practice_round, .2, true).round
    app._practice_last_tick = app._practice_now()
    var previous_pause_calls := app.pause_calls
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
    check(app.pause_calls == previous_pause_calls + 1, "one OS notification invokes inherited Practice pause exactly once")
    var practice_held: float = app._practice_round.phase
    app._process(25.0)
    app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
    app._process(25.0)
    check(app._practice_round.state == "paused" and app._practice_round.phase == practice_held, "background and music resume preserve explicit Practice hold")
    app._practice_resume()
    app._practice_round = Practice.tick(app._practice_round, (TAU / 3.0) / 1.2 - practice_held / 1.2, true).round
    app._practice_last_tick = app._practice_now()
    app._practice_action()
    check(audio.result_player.stream == audio.hit_stream and audio.result_player.playing, "only actual saved Practice hit plays hit effect")
    await wait_effect(audio.result_player)
    app._practice_retry()
    check(not audio.result_player.playing, "repeated retry cannot replay committed result")
    app._practice_next(); app._practice_action()
    app._practice_store = Archive.new(app.path + ".practice.json", func(_path: String, _bytes: PackedByteArray) -> Error: return ERR_CANT_CREATE)
    app._practice_action()
    check(not app._practice_pending.is_empty() and not audio.result_player.playing, "failed Practice save cannot sound like a published result")
    app._practice_store = Archive.new(app.path + ".practice.json")
    app._practice_retry()
    check(audio.result_player.playing and audio.result_player.stream == audio.miss_stream, "successful explicit retry emits one actual miss")
    app._practice_exit(); app._open_settings()
    for viewport in [Vector2i(1080, 1920), Vector2i(540, 720), Vector2i(320, 640)]:
        root.size = viewport
        app._audio_layout_settings()
        await process_frame
        await process_frame
        var scroll_rect := app._audio_settings_scroll.get_global_rect()
        check(scroll_rect.encloses(app._audio_music_button.get_global_rect()) and scroll_rect.encloses(app._audio_sound_button.get_global_rect()), "both switches are reachable at " + str(viewport))
        check(app._audio_music_button.get_global_rect().size.y >= 48.0, "switch touch height at " + str(viewport))
        check(app._audio_status.get_global_rect().position.y >= app._audio_sound_button.get_global_rect().end.y, "status never overlaps the actual switches")
        check(not scroll_rect.intersects(app._audio_settings_back.get_global_rect()), "fixed Back never overlaps scrolling content")
        app._audio_settings_scroll.scroll_vertical = int(app._audio_settings_scroll.get_v_scroll_bar().max_value)
        await process_frame
        check(scroll_rect.encloses(app.remove_ads_button.get_global_rect()), "existing final Settings card remains reachable")
        app._audio_settings_scroll.scroll_vertical = 0
    app.queue_free()
    await process_frame
    var malformed := ConfigFile.new()
    malformed.set_value("audio", "music", "false")
    malformed.set_value("audio", "sound", 0)
    malformed.save(folder.path_join("malformed.cfg"))
    var invalid = Audio.new()
    invalid.settings_path = folder.path_join("malformed.cfg")
    root.add_child(invalid)
    check(invalid.music_enabled and invalid.sound_enabled, "wrong persisted types cannot silently become settings")
    invalid.queue_free()
    await process_frame
    # Let Dummy's mixer release stopped playback references before engine exit.
    await create_timer(.2).timeout
    if failures == 0: print("NN AUDIO PASS checks=", checks)
    quit(0 if failures == 0 else 1)
