extends SceneTree
# Catches the production endpoint consuming stale QOA decoder scratch after the
# final logical frame. The runner supplies exact hashed exported .sample files.
class ExportedAudio extends "res://audio_service.gd":
    func _wav(filename: String) -> AudioStreamWAV:
        return load("res://exported/" + filename + ".sample") as AudioStreamWAV
const FRAMES := 529200
const RATE := 22050
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok: failures += 1; printerr("FAIL ", message)
func _initialize() -> void: call_deferred("run")
func mix_loop(stream: AudioStreamWAV, count: int, start: float = 0.0) -> Dictionary:
    var playback := stream.instantiate_playback()
    playback.start(start)
    var data := PackedVector2Array()
    var chunks := [1, 17, 511, 2048, 4095]
    var calls := 0
    var wraps := 0
    var previous := start
    while data.size() < count:
        var requested := mini(chunks[calls % chunks.size()], count - data.size())
        var part := playback.mix_audio(1.0, requested)
        data.append_array(part)
        var position := playback.get_playback_position()
        if position < previous: wraps += 1
        previous = position
        calls += 1
        if part.size() != requested: break
    check(data.size() == count and playback.is_playing(), "actual exported loop stays active and returns every requested frame")
    playback.stop()
    check(not playback.is_playing(), "explicit stop ends the real playback instance")
    playback.start()
    var restarted := playback.mix_audio(1.0, 128)
    if start == 0.0: check(restarted == data.slice(0, 128), "restart reproduces the original beginning")
    playback.stop()
    return {"data": data, "wraps": wraps, "calls": calls}
func run() -> void:
    var imported := load("res://exported/precision-loop.wav.sample") as AudioStreamWAV
    check(imported != null and imported.format == AudioStreamWAV.FORMAT_QOA and not imported.stereo and imported.mix_rate == RATE and imported.get_length() == 24.0, "actual exported mono QOA has529200logical frames at22050Hz")
    var original_data := imported.data.duplicate()
    var audio := ExportedAudio.new()
    audio.settings_path = OS.get_cmdline_user_args()[0].path_join("isolated-audio.cfg")
    root.add_child(audio) # Actual production _ready creates/configures its Music stream.
    audio.music_player.stop() # Test the stream directly, with no real output device.
    var music := audio.music_player.stream as AudioStreamWAV
    check(music.data == original_data and music.get_length() == 24.0, "production setup keeps all original encoded data and stored24seconds")
    check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.loop_begin == 0 and music.loop_end >= 0 and music.loop_end < FRAMES, "production endpoint names an encoded logical frame")
    var mixed := mix_loop(music, FRAMES * 3 + 1037)
    var data: PackedVector2Array = mixed.data
    check(mixed.wraps >= 3, "actual mixer crosses at least three loop boundaries")
    var finite := true
    var peak := 0.0
    var step := 0.0
    var previous := 0.0
    for frame in data:
        finite = finite and is_finite(frame.x) and is_finite(frame.y) and frame.x == frame.y
        peak = maxf(peak, absf(frame.x)); step = maxf(step, absf(frame.x - previous)); previous = frame.x
    check(finite and peak > .02 and peak < .6 and step < .1, "all mixed samples are finite mono nonzero with headroom and no new discontinuity")
    # Independently decoded fixed resource: first two logical samples are+1/-1.
    # At rate1 Godot's cubic history delays these by2frames. Old end=N instead
    # emits -360/32767 from prior QOA scratch at this exact boundary.
    check(data.size() > FRAMES + 2 and absf(data[FRAMES + 2].x - (-1.0 / 32767.0)) < .000000001, "loop boundary emits encoded audio rather than the stale -360 scratch sample")
    var periodic := true
    for index in range(FRAMES + 128, FRAMES * 2 - 128):
        if data[index] != data[index + 529199]: periodic = false; break
    check(periodic, "second and third cycles repeat the last-valid529199frame period")
    var near := mix_loop(music, RATE, 23.999)
    var near_safe := true
    for frame in near.data: near_safe = near_safe and is_finite(frame.x) and absf(frame.x) < .6
    check(near_safe, "starting just before the logical end wraps with bounded actual QOA output")
    print("NINE QOA METRICS logicalFrames=", FRAMES, " endpoint=", music.loop_end, " mixedFrames=", data.size(), " wraps=", mixed.wraps, " peak=", peak, " maxStep=", step, " steadyPeriodFrames=529199 steadyPeriodSeconds=", 529199.0 / RATE, " boundarySample=", data[FRAMES + 2].x)
    audio.queue_free()
    await process_frame
    await create_timer(.1).timeout
    print("NINE EXPORTED QOA LOOP checks=", checks, " failures=", failures)
    if failures == 0: print("NINE EXPORTED QOA LOOP PASS checks=", checks)
    quit(0 if failures == 0 else 1)
