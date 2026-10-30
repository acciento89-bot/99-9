extends SceneTree
# A regression here means real viewport touch propagation broke. No handler
# calls, synthetic pressed signals or scrollbar setters stand in for a swipe.
class Probe extends "res://scripts/main_audio.gd":
    var path: String
    func _audio_settings_path() -> String: return path + ".cfg"
    func _practice_archive_path() -> String: return path + ".practice.json"
    func _load_save() -> void: player_id = "settings-touch-qa"
    func _save() -> void: pass
class Rankings extends Node:
    signal leaderboard_loaded(mode: String, top: Array, me: Variant)
    signal leaderboard_failed(message: String)
    signal score_submitted(player: Dictionary)
    signal score_submit_failed(message: String)
    signal name_saved(player: Dictionary)
    signal name_save_failed(message: String)
    var saves := 0
    func save_name(_id: String, requested: String) -> void:
        saves += 1
        name_saved.emit({"display_name": requested})
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
    var purchases := 0
    func start_store() -> void: pass
    func get_display_price(_id: String) -> String: return ""
    func purchase_remove_ads() -> void: purchases += 1
class Ads extends Node:
    signal interstitial_closed
    signal ad_error(message: String)
    var privacy_calls := 0
    func start_ads() -> void: pass
    func set_ads_removed(_owned: bool) -> void: pass
    func show_privacy_options() -> void: privacy_calls += 1
var checks := 0
var failures := 0
var route: Array[String] = []
func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("FAIL " + message)
func _initialize() -> void: call_deferred("run_checks")
func trace_tree(node: Node) -> void:
    if node is Control:
        node.gui_input.connect(func(event: InputEvent) -> void:
            if event is InputEventScreenTouch or event is InputEventScreenDrag:
                var path := str(node.get_path())
                if not route.has(path): route.append(path))
    for child in node.get_children(): trace_tree(child)
func touch(position: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = 0; event.position = position; event.pressed = pressed
    root.push_input(event, true)
func swipe(origin: Vector2, distance: float) -> void:
    route.clear()
    touch(origin, true)
    for step in range(1, 9):
        var drag := InputEventScreenDrag.new()
        drag.index = 0; drag.position = origin - Vector2(0, distance * step / 8)
        drag.relative = Vector2(0, -distance / 8)
        root.push_input(drag, true)
        await process_frame
    touch(origin - Vector2(0, distance), false)
    await process_frame
func tap(button: Control) -> void:
    var point := button.get_global_rect().get_center()
    touch(point, true); touch(point, false)
    await process_frame
func reset_top(app: Probe) -> void:
    # Setup between independent gestures only; assertions below always depend
    # on real touch events, including bringing the final card fully into view.
    app._audio_settings_scroll.scroll_vertical = 0
    await process_frame
func find_button(node: Node, text: String) -> Button:
    if node is Button and node.text == text: return node
    for child in node.get_children():
        var found := find_button(child, text)
        if found != null: return found
    return null
func run_checks() -> void:
    var app := Probe.new()
    app.path = OS.get_cmdline_user_args()[0].path_join("settings")
    for entry in [[Rankings.new(), "LeaderboardService"], [Billing.new(), "IapService"], [Ads.new(), "AdsService"]]:
        entry[0].name = entry[1]; app.add_child(entry[0])
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.size = Vector2i(1080, 1920)
    root.add_child(app)
    await process_frame
    await process_frame
    app.set_process(false)
    app._open_settings()
    trace_tree(app.settings_layer)
    for viewport in [Vector2i(1080, 1920), Vector2i(540, 720), Vector2i(320, 640)]:
        root.size = viewport; app._audio_layout_settings()
        await process_frame
        await process_frame
        await reset_top(app)
        var bounds := app._audio_settings_scroll.get_global_rect()
        var origin := Vector2(viewport.x * 90.0 / 1080.0, bounds.end.y - 40)
        await swipe(origin, minf(420, bounds.size.y * .65))
        print("NN_SETTINGS_TRACE edge viewport=", viewport, " scroll=", app._audio_settings_scroll.scroll_vertical, " route=", route)
        check(app._audio_settings_scroll.scroll_vertical > 0, "blank edge swipe scrolls the actual Settings at " + str(viewport))
        check(route.has(str(app._audio_settings_scroll.get_path())), "blank edge touch reaches the owning scroll through every Control")
        # Only repeated real swipes, no max_value/setter, expose the final card.
        for attempt in range(12):
            if bounds.encloses(app.remove_ads_button.get_global_rect()): break
            await swipe(origin, minf(420, bounds.size.y * .65))
        check(bounds.encloses(app.remove_ads_button.get_global_rect()), "touch alone fully exposes Remove Ads at " + str(viewport))
        await reset_top(app)
        origin = app._audio_panel.get_global_rect().end - Vector2(app._audio_panel.get_global_rect().size.x / 2, 15)
        await swipe(origin, minf(180, origin.y - bounds.position.y - 20))
        print("NN_SETTINGS_TRACE card viewport=", viewport, " scroll=", app._audio_settings_scroll.scroll_vertical, " route=", route)
        check(app._audio_settings_scroll.scroll_vertical > 0, "center card swipe scrolls through ignored decoration and canvas")
        await reset_top(app)
        var before: bool = app._audio.music_enabled
        origin = app._audio_music_button.get_global_rect().get_center()
        await swipe(origin, 24)
        print("NN_SETTINGS_TRACE button viewport=", viewport, " scroll=", app._audio_settings_scroll.scroll_vertical, " route=", route)
        check(app._audio_settings_scroll.scroll_vertical > 0, "button-origin drag reaches Settings scroll")
        check(app._audio.music_enabled == before, "drag ending within Music cancels its click")
        check(app._audio_settings_scroll.finger == -1 and not app._audio_settings_scroll.scrolling, "released touch leaves no scroll gesture captured")
    root.size = Vector2i(1080, 1920); app._audio_layout_settings()
    await process_frame
    await process_frame
    await reset_top(app)
    for title in ["SAVE PLAYER NAME", "OPEN", "PRIVACY OPTIONS"]:
        app._open_settings()
        await process_frame
        var button := find_button(app.settings_layer, title)
        check(button != null, "original actual Settings action exists: " + title)
        var saves_before: int = app.leaderboard_service.saves
        var privacy_before: int = app.ads_service.privacy_calls
        await swipe(button.get_global_rect().get_center(), 24)
        check(app._audio_settings_scroll.scroll_vertical > 0, "original action drag scrolls: " + title)
        check(app.screen == app.AppScreen.SETTINGS and app.leaderboard_service.saves == saves_before and app.ads_service.privacy_calls == privacy_before, "drag cancels original action callback: " + title)
        await reset_top(app)
    app._open_settings()
    await process_frame
    var before_music: bool = app._audio.music_enabled
    await tap(app._audio_music_button)
    check(app._audio.music_enabled != before_music, "ordinary released Music tap retains the real preference callback")
    await tap(app.name_input)
    check(app.name_input.has_focus(), "actual player-name field remains editable by touch")
    app.name_input.text = "SOURCE QA"
    var saves_before: int = app.leaderboard_service.saves
    await tap(find_button(app.settings_layer, "SAVE PLAYER NAME"))
    check(app.leaderboard_service.saves == saves_before + 1 and app.player_name == "SOURCE QA", "ordinary player-name Save retains original callback and response")
    await tap(find_button(app.settings_layer, "OPEN"))
    check(app.screen == app.AppScreen.THEMES, "ordinary Designs tap retains original navigation callback")
    app._open_settings()
    await process_frame
    await tap(app._audio_settings_back)
    check(app.screen == app.AppScreen.MENU, "fixed Back retains original navigation callback")
    check(app.iap_service.purchases == 0, "no gesture invokes purchase even in inert test provider")
    app.queue_free()
    await process_frame
    await create_timer(.2).timeout
    print("NN SETTINGS TOUCH checks=", checks, " failures=", failures)
    if failures == 0: print("NN SETTINGS TOUCH PASS checks=", checks)
    quit(0 if failures == 0 else 1)
