extends SceneTree
# Source integration fixture only: actual UI/model/archive, isolated temporary
# file and inert providers. No native/device/SDK/earned arcade evidence.
const Practice = preload("res://scripts/practice_model.gd")
const Archive = preload("res://scripts/practice_archive.gd")
class Probe extends "res://scripts/main_practice.gd":
    var path: String
    func _practice_now() -> int: return 1000000
    var legacy_writes := 0
    func _load_save() -> void: player_id = "qa-player"
    func _save() -> void: legacy_writes += 1
    func _practice_archive_path() -> String: return path
class Rankings extends Node:
    signal leaderboard_loaded(mode: String, top: Array, me: Variant)
    signal leaderboard_failed(message: String)
    signal score_submitted(player: Dictionary)
    signal score_submit_failed(message: String)
    signal name_saved(player: Dictionary)
    signal name_save_failed(message: String)
    var submissions := 0
    func submit_score(_a: String, _b: int, _c: String, _d: String) -> void: submissions += 1
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
func make_app(path: String) -> Probe:
    var app := Probe.new()
    app.path = path
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var rankings := Rankings.new()
    rankings.name = "LeaderboardService"
    app.add_child(rankings)
    var billing := Billing.new()
    billing.name = "IapService"
    app.add_child(billing)
    var ads := Ads.new()
    ads.name = "AdsService"
    app.add_child(ads)
    root.add_child(app)
    return app
func _initialize() -> void:
    call_deferred("run_checks")
func run_checks() -> void:
    var path: String = OS.get_cmdline_user_args()[0].path_join("integration-practice.json")
    var app := make_app(path)
    await process_frame
    app.best_value = 99.95
    app.best_streak = 9
    app.games_played = 24
    app.streak = 3
    app.rounds_since_interstitial = 5
    var old_writes := app.legacy_writes
    app._practice_open_menu()
    app._practice_begin(1)
    check(app._practice_book.active != null and app._practice_book.active.round.state == "ready", "explicit start persists separate session")
    app._practice_action()
    check(app._practice_round.state == "running", "actual practice start action")
    app._practice_round = Practice.tick(app._practice_round, (TAU / 3.0) / 1.2, true).round
    app._practice_last_tick = app._practice_now()
    print("NN_UI_DIAGNOSTIC before-stop round=", app._practice_round, " focused=", app._practice_focused)
    app._practice_action()
    print("NN_UI_DIAGNOSTIC after-stop book=", app._practice_book, " error=", app._practice_error, " pending=", app._practice_pending)
    check(app._practice_book.active.outcomes.size() == 1 and app._practice_book.active.outcomes[0].hit, "actual UI stop publishes one saved outcome")
    check(app.best_value == 99.95 and app.best_streak == 9 and app.games_played == 24 and app.streak == 3, "practice leaves all old arcade counters intact")
    check(app.legacy_writes == old_writes and app.rounds_since_interstitial == 5 and app.get_node("LeaderboardService").submissions == 0, "practice never calls legacy save/rankings/ad round accounting")
    app._practice_next()
    app._practice_action()
    app._practice_round = Practice.tick(app._practice_round, .2, true).round
    app._practice_last_tick = app._practice_now()
    app._practice_pause()
    print("NN_UI_DIAGNOSTIC after-pause round=", app._practice_round, " error=", app._practice_error, " pending=", app._practice_pending)
    var held: float = app._practice_round.phase
    check(app._practice_round.state == "paused" and held > 0, "pause durably holds current phase")
    app._practice_exit()
    var second := make_app(path)
    await process_frame
    second._practice_open_menu()
    check(second._practice_round.state == "paused" and second._practice_round.phase == held, "cold resume holds exact saved phase behind explicit resume")
    second._practice_resume()
    check(second._practice_round.state == "running" and second._practice_round.phase == held, "explicit resume cannot charge loading gap")
    second._practice_de = true
    second._practice_render()
    check(second._practice_title.text.contains("TRAINING") and not second._practice_status.text.is_empty(), "actual German UI labels rendered")
    second._practice_store = Archive.new(path, func(_path: String, _bytes: PackedByteArray) -> Error: return ERR_CANT_CREATE)
    second._practice_round.phase = 0.253344
    second._practice_action()
    check(second._practice_book.active.outcomes.size() == 1 and not second._practice_pending.is_empty(), "actual UI failed stop does not publish proposed result")
    check(Archive.new(path).read_book().book.active.outcomes.size() == 1, "failed UI stop leaves durable prior outcome count")
    second._practice_store = Archive.new(path)
    second._practice_retry()
    print("NN_UI_DIAGNOSTIC after-retry book=", second._practice_book, " error=", second._practice_error, " pending=", second._practice_pending, " disk=", Archive.new(path).read_book())
    check(second._practice_book.active.outcomes.size() == 2 and second._practice_pending.is_empty(), "explicit retry publishes exactly one durable held result")
    second._practice_retry()
    check(second._practice_book.active.outcomes.size() == 2, "repeated retry cannot duplicate result")
    app.queue_free()
    second.queue_free()
    await process_frame
    await touch_navigation_checks(path + ".touch")
    if failures == 0: print("NN PRACTICE INTEGRATION PASS checks=", checks)
    quit(0 if failures == 0 else 1)

# Actual engine GUI event propagation, not direct pressed.emit()/handler calls.
func send_touch(position: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = 0
    event.position = position
    event.pressed = pressed
    root.push_input(event, true)

func practice_button(app: Probe, prefix: String) -> Button:
    for child in app._practice_content.get_children():
        if child is Button and child.text.begins_with(prefix): return child
    return null

func touch_navigation_checks(path: String) -> void:
    root.size = Vector2i(540, 720)
    var app := make_app(path)
    await process_frame
    app._practice_open_menu()
    await process_frame
    await process_frame
    var stage := practice_button(app, "1 ·")
    check(stage != null and app._practice_scroll.get_v_scroll_bar().max_value > app._practice_scroll.size.y, "compact actual GUI has scrollable stages")
    var origin := stage.get_global_rect().get_center()
    send_touch(origin, true)
    await process_frame
    check(app._practice_book.active == null, "finger down on stage does not prematurely begin a session")
    for step in range(1, 7):
        var drag := InputEventScreenDrag.new()
        drag.index = 0
        drag.position = origin - Vector2(0, step * 14)
        drag.relative = Vector2(0, -14)
        root.push_input(drag, true)
        await process_frame
    send_touch(origin - Vector2(0, 84), false)
    await process_frame
    check(app._practice_scroll.scroll_vertical > 0 and app._practice_book.active == null, "drag across stage scrolls without navigation")
    app._practice_scroll.scroll_vertical = 0
    await process_frame
    origin = stage.get_global_rect().get_center()
    send_touch(origin, true)
    # Android may drop the release while backgrounded. A subsequent pointer
    # with another ID must still be able to scroll after focus returns.
    app._practice_scroll.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
    app._practice_scroll.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
    var resumed_touch := InputEventScreenTouch.new()
    resumed_touch.index = 1
    resumed_touch.position = origin
    resumed_touch.pressed = true
    root.push_input(resumed_touch, true)
    for step in range(1, 7):
        var resumed_drag := InputEventScreenDrag.new()
        resumed_drag.index = 1
        resumed_drag.position = origin - Vector2(0, step * 14)
        resumed_drag.relative = Vector2(0, -14)
        root.push_input(resumed_drag, true)
        await process_frame
    check(app._practice_scroll.scroll_vertical > 0 and app._practice_book.active == null, "dropped background release cannot block the next scroll gesture")
    resumed_touch.pressed = false
    resumed_touch.position = origin - Vector2(0, 84)
    root.push_input(resumed_touch, true)
    send_touch(origin, false)
    if app._practice_book.active == null:
        app._practice_scroll.scroll_vertical = 0
        await process_frame
        origin = stage.get_global_rect().get_center()
        send_touch(origin, true)
        await process_frame
        check(app._practice_book.active == null, "ordinary stage tap waits for release")
        send_touch(origin, false)
        await process_frame
        check(app._practice_book.active != null and app._practice_book.active.round.state == "ready", "ordinary released tap begins one saved session")
        await process_frame
        var start := practice_button(app, "START")
        origin = start.get_global_rect().get_center()
        send_touch(origin, true)
        await process_frame
        check(app._practice_round.state == "running", "timing start remains immediate on finger down")
        send_touch(origin, false)
    app.queue_free()
    await process_frame
