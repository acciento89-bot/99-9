extends "res://scripts/main_v7.gd"

# Release polish pass: achievements, native-friendly sharing and richer local stats.

var total_score_sum := 0.0
var tracked_rounds := 0
var hits_99_plus := 0
var hits_999_plus := 0
var unlocked_achievements: Array[String] = []

var share_result_button: Button
var stats_average_value_label: Label
var stats_99_value_label: Label
var stats_999_value_label: Label
var stats_achievement_value_label: Label
var stats_share_status_label: Label

var achievements_layer: Control
var achievements_rows: VBoxContainer
var achievements_progress_label: Label
var achievements_open := false


func _ready() -> void:
    super._ready()
    var changed := _check_achievements(false)
    if changed:
        _save()
    _refresh_stats_screen()


func _build_game_ui() -> void:
    super._build_game_ui()

    share_result_button = _make_button("SHARE RESULT", Vector2(390, 88), 25, "secondary")
    _place(share_result_button, Vector2(345, 1505), Vector2(390, 88), gameplay_layer)
    share_result_button.visible = false
    share_result_button.pressed.connect(_share_current_result)


func _build_stats_ui() -> void:
    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), stats_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    var eyebrow := _make_muted_label("PERSONAL RECORDS · ALL-TIME", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 125), Vector2(760, 40), stats_layer)

    var title := _make_label("YOUR STATS", 64, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 165), Vector2(880, 90), stats_layer)

    stats_best_value_label = _make_stat_card("BEST HIT", "0.000%", Vector2(130, 305))
    stats_average_value_label = _make_stat_card("AVG HIT", "—", Vector2(560, 305))
    stats_streak_value_label = _make_stat_card("LONGEST STREAK", "0", Vector2(130, 515))
    stats_rounds_value_label = _make_stat_card("ROUNDS PLAYED", "0", Vector2(560, 515))
    stats_99_value_label = _make_stat_card("99%+ HITS", "0", Vector2(130, 725))
    stats_999_value_label = _make_stat_card("99.9%+ HITS", "0", Vector2(560, 725))
    stats_perfect_value_label = _make_stat_card("PERFECT HITS", "0", Vector2(130, 935))
    stats_achievement_value_label = _make_stat_card("ACHIEVEMENTS", "0 / 9", Vector2(560, 935))

    var player_card := _make_panel("soft")
    _place(player_card, Vector2(130, 1165), Vector2(820, 145), stats_layer)
    var player_cap := _make_muted_label("PLAYER", 19, HORIZONTAL_ALIGNMENT_CENTER)
    _place(player_cap, Vector2(30, 18), Vector2(760, 36), player_card)
    stats_player_label = _make_label(player_name, 34, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_player_label, Vector2(30, 54), Vector2(760, 70), player_card)

    var achievements := _make_button("ACHIEVEMENTS", Vector2(390, 90), 25, "secondary")
    _place(achievements, Vector2(130, 1350), Vector2(390, 90), stats_layer)
    achievements.pressed.connect(_open_achievements)

    var share_best := _make_button("SHARE BEST", Vector2(390, 90), 25, "secondary")
    _place(share_best, Vector2(560, 1350), Vector2(390, 90), stats_layer)
    share_best.pressed.connect(_share_best_result)

    var leaderboard := _make_button("OPEN WORLD RANKING", Vector2(820, 90), 27, "secondary")
    _place(leaderboard, Vector2(130, 1470), Vector2(820, 90), stats_layer)
    leaderboard.pressed.connect(func() -> void: _open_leaderboard("hit"))

    stats_share_status_label = _make_muted_label("Stats are saved locally on this device.", 19, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_share_status_label, Vector2(130, 1585), Vector2(820, 65), stats_layer)

    _build_achievements_ui()


func _make_stat_card(caption: String, initial_value: String, pos: Vector2) -> Label:
    var card := _make_panel("card")
    _place(card, pos, Vector2(390, 185), stats_layer)
    var cap := _make_muted_label(caption, 19, HORIZONTAL_ALIGNMENT_CENTER)
    _place(cap, Vector2(25, 25), Vector2(340, 40), card)
    var value := _make_label(initial_value, 39, HORIZONTAL_ALIGNMENT_CENTER)
    _place(value, Vector2(20, 72), Vector2(350, 75), card)
    return value


func _build_achievements_ui() -> void:
    achievements_layer = _full_layer()
    achievements_layer.visible = false

    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), achievements_layer)
    back.pressed.connect(_close_achievements)

    var eyebrow := _make_muted_label("MILESTONES", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 125), Vector2(760, 40), achievements_layer)

    var title := _make_label("ACHIEVEMENTS", 60, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(90, 165), Vector2(900, 90), achievements_layer)

    achievements_progress_label = _make_muted_label("0 / 9 UNLOCKED", 22, HORIZONTAL_ALIGNMENT_CENTER)
    _place(achievements_progress_label, Vector2(120, 260), Vector2(840, 48), achievements_layer)

    var list_panel := _make_panel("soft")
    _place(list_panel, Vector2(95, 335), Vector2(890, 1280), achievements_layer)

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(24, 24)
    scroll.size = Vector2(842, 1232)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    list_panel.add_child(scroll)

    achievements_rows = VBoxContainer.new()
    achievements_rows.custom_minimum_size = Vector2(820, 0)
    achievements_rows.add_theme_constant_override("separation", 14)
    scroll.add_child(achievements_rows)

    var footer := _make_muted_label("Every achievement is earned through normal gameplay.", 19, HORIZONTAL_ALIGNMENT_CENTER)
    _place(footer, Vector2(120, 1650), Vector2(840, 60), achievements_layer)


func _achievement_definitions() -> Array[Dictionary]:
    return [
        {"id": "first_tap", "name": "FIRST TAP", "desc": "Finish your first round."},
        {"id": "warmup", "name": "WARMED UP", "desc": "Play 25 rounds."},
        {"id": "century", "name": "CENTURY", "desc": "Play 100 rounds."},
        {"id": "ninety_nine", "name": "SO CLOSE", "desc": "Hit 99.000% or better."},
        {"id": "club", "name": "99.9 CLUB", "desc": "Hit 99.900% or better."},
        {"id": "absurd", "name": "ABSURDLY CLOSE", "desc": "Hit 99.990% or better."},
        {"id": "perfect", "name": "PERFECT", "desc": "Hit exactly 100.000%."},
        {"id": "on_fire", "name": "ON FIRE", "desc": "Reach a 5-round 99.9% streak."},
        {"id": "unstoppable", "name": "UNSTOPPABLE", "desc": "Reach a 10-round 99.9% streak."},
    ]


func _achievement_is_earned(id: String) -> bool:
    match id:
        "first_tap": return games_played >= 1
        "warmup": return games_played >= 25
        "century": return games_played >= 100
        "ninety_nine": return best_value >= 99.000
        "club": return best_value >= STREAK_THRESHOLD
        "absurd": return best_value >= 99.990
        "perfect": return local_perfect_count >= 1
        "on_fire": return best_streak >= 5
        "unstoppable": return best_streak >= 10
        _: return false


func _check_achievements(show_notice: bool) -> bool:
    var changed := false
    var newest_name := ""
    for definition in _achievement_definitions():
        var id := str(definition["id"])
        if _achievement_is_earned(id) and not unlocked_achievements.has(id):
            unlocked_achievements.append(id)
            newest_name = str(definition["name"])
            changed = true
    if changed and show_notice and not newest_name.is_empty():
        result_detail_label.text = "%s\nACHIEVEMENT UNLOCKED · %s" % [result_subtitle, newest_name]
    return changed


func _refresh_achievements_screen() -> void:
    if achievements_rows == null:
        return
    for child in achievements_rows.get_children():
        child.queue_free()

    var definitions := _achievement_definitions()
    if achievements_progress_label != null:
        achievements_progress_label.text = "%d / %d UNLOCKED" % [unlocked_achievements.size(), definitions.size()]

    for definition in definitions:
        var id := str(definition["id"])
        var unlocked := unlocked_achievements.has(id)
        var panel := _make_panel("row")
        panel.custom_minimum_size = Vector2(820, 125)

        var icon := _make_label("✓" if unlocked else "·", 36, HORIZONTAL_ALIGNMENT_CENTER)
        icon.custom_minimum_size = Vector2(85, 125)
        if unlocked:
            icon.add_theme_color_override("font_color", _theme_colors(active_theme_id)["success"])
        panel.add_child(icon)

        var name := _make_label(str(definition["name"]), 25, HORIZONTAL_ALIGNMENT_LEFT)
        name.position = Vector2(100, 14)
        name.size = Vector2(675, 48)
        panel.add_child(name)

        var desc := _make_muted_label(str(definition["desc"]), 19, HORIZONTAL_ALIGNMENT_LEFT)
        desc.position = Vector2(100, 62)
        desc.size = Vector2(675, 44)
        panel.add_child(desc)

        achievements_rows.add_child(panel)

    _apply_theme_to_controls()


func _open_achievements() -> void:
    achievements_open = true
    stats_layer.visible = false
    achievements_layer.visible = true
    _refresh_achievements_screen()
    queue_redraw()


func _close_achievements() -> void:
    achievements_open = false
    achievements_layer.visible = false
    stats_layer.visible = true
    _refresh_stats_screen()
    queue_redraw()


func _show_screen(target: AppScreen) -> void:
    super._show_screen(target)
    if achievements_layer != null:
        if target != AppScreen.STATS:
            achievements_open = false
            achievements_layer.visible = false
        elif not achievements_open:
            achievements_layer.visible = false


func _reset_to_ready() -> void:
    super._reset_to_ready()
    if share_result_button != null:
        share_result_button.visible = false
        share_result_button.text = "SHARE RESULT"


func _start_round() -> void:
    super._start_round()
    if share_result_button != null:
        share_result_button.visible = false
        share_result_button.text = "SHARE RESULT"


func _stop_round() -> void:
    super._stop_round()

    total_score_sum += result_value
    tracked_rounds += 1
    if result_value >= 99.000:
        hits_99_plus += 1
    if result_value >= STREAK_THRESHOLD:
        hits_999_plus += 1

    _check_achievements(true)
    _save()
    _refresh_stats_screen()

    if share_result_button != null:
        share_result_button.visible = true
        share_result_button.text = "SHARE RESULT"


func _refresh_stats_screen() -> void:
    super._refresh_stats_screen()
    if stats_average_value_label != null:
        stats_average_value_label.text = _format_percent(total_score_sum / float(tracked_rounds)) if tracked_rounds > 0 else "—"
    if stats_99_value_label != null:
        stats_99_value_label.text = str(hits_99_plus)
    if stats_999_value_label != null:
        stats_999_value_label.text = str(hits_999_plus)
    if stats_achievement_value_label != null:
        stats_achievement_value_label.text = "%d / %d" % [unlocked_achievements.size(), _achievement_definitions().size()]


func _share_current_result() -> void:
    if state != GameState.RESULT:
        return
    await _share_result_value(result_value, streak)


func _share_best_result() -> void:
    if best_value <= 0.0:
        if stats_share_status_label != null:
            stats_share_status_label.text = "PLAY A ROUND FIRST, THEN SHARE YOUR BEST."
        return
    await _share_result_value(best_value, best_streak)


func _share_result_value(value: float, streak_value: int) -> void:
    var message := "I hit %s in 99.9%% — can you get closer?" % _format_percent(value)
    if streak_value > 1:
        message += " My streak: %d." % streak_value

    var image_path := await _create_share_card(value, streak_value)
    var shared := false

    for singleton_name in ["Share", "GodotShare"]:
        if not Engine.has_singleton(singleton_name):
            continue
        var native_share = Engine.get_singleton(singleton_name)
        if native_share != null and native_share.has_method("share_image") and not image_path.is_empty():
            native_share.call("share_image", image_path, "99.9%", "My 99.9% result", message)
            shared = true
            break
        if native_share != null and native_share.has_method("share_text"):
            native_share.call("share_text", "99.9%", "My 99.9% result", message)
            shared = true
            break

    if not shared:
        DisplayServer.clipboard_set(message)
        if OS.get_name() == "iOS":
            # Safe fallback for builds where the native share plugin is not bundled yet.
            OS.shell_open("sms:&body=" + message.uri_encode())
        if stats_share_status_label != null:
            stats_share_status_label.text = "RESULT COPIED · READY TO SHARE"


func _create_share_card(value: float, streak_value: int) -> String:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1080, 1080)
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    viewport.transparent_bg = false
    add_child(viewport)

    var root := Control.new()
    root.size = Vector2(1080, 1080)
    viewport.add_child(root)

    var colors := _theme_colors(active_theme_id)
    var bg := ColorRect.new()
    bg.color = colors["bg"]
    bg.size = Vector2(1080, 1080)
    root.add_child(bg)

    var accent_bar := ColorRect.new()
    accent_bar.color = colors["accent"]
    accent_bar.position = Vector2(90, 105)
    accent_bar.size = Vector2(900, 8)
    root.add_child(accent_bar)

    var logo := _make_label("99.9%", 105, HORIZONTAL_ALIGNMENT_CENTER)
    logo.position = Vector2(90, 150)
    logo.size = Vector2(900, 140)
    root.add_child(logo)

    var caption := _make_muted_label("HOW CLOSE CAN YOU GET?", 31, HORIZONTAL_ALIGNMENT_CENTER)
    caption.position = Vector2(90, 290)
    caption.size = Vector2(900, 60)
    root.add_child(caption)

    var score := _make_label(_format_percent(value), 104, HORIZONTAL_ALIGNMENT_CENTER)
    score.position = Vector2(70, 420)
    score.size = Vector2(940, 150)
    score.add_theme_color_override("font_color", colors["success"] if value >= STREAK_THRESHOLD else colors["text"])
    root.add_child(score)

    var detail_text := "PERSONAL BEST" if is_equal_approx(value, best_value) else "ROUND RESULT"
    if streak_value > 1:
        detail_text += " · STREAK %d" % streak_value
    var detail := _make_muted_label(detail_text, 30, HORIZONTAL_ALIGNMENT_CENTER)
    detail.position = Vector2(90, 590)
    detail.size = Vector2(900, 70)
    root.add_child(detail)

    var challenge := _make_label("CAN YOU BEAT IT?", 42, HORIZONTAL_ALIGNMENT_CENTER)
    challenge.position = Vector2(90, 760)
    challenge.size = Vector2(900, 80)
    root.add_child(challenge)

    var brand := _make_muted_label("99.9% · KAMILUNAVO GAMES", 24, HORIZONTAL_ALIGNMENT_CENTER)
    brand.position = Vector2(90, 900)
    brand.size = Vector2(900, 60)
    root.add_child(brand)

    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    var path := "user://share_result.png"
    var error := image.save_png(path)
    viewport.queue_free()
    if error != OK:
        return ""
    return ProjectSettings.globalize_path(path)


func _load_save() -> void:
    super._load_save()
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return

    total_score_sum = float(parsed.get("total_score_sum", 0.0))
    tracked_rounds = int(parsed.get("tracked_rounds", 0))
    hits_99_plus = int(parsed.get("hits_99_plus", 0))
    hits_999_plus = int(parsed.get("hits_999_plus", 0))

    unlocked_achievements.clear()
    var saved_achievements = parsed.get("unlocked_achievements", [])
    if typeof(saved_achievements) == TYPE_ARRAY:
        for raw_id in saved_achievements:
            var id := str(raw_id)
            if not unlocked_achievements.has(id):
                unlocked_achievements.append(id)


func _save() -> void:
    super._save()
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var read_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if read_file == null:
        return
    var parsed = JSON.parse_string(read_file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        parsed = {}

    parsed["total_score_sum"] = total_score_sum
    parsed["tracked_rounds"] = tracked_rounds
    parsed["hits_99_plus"] = hits_99_plus
    parsed["hits_999_plus"] = hits_999_plus
    parsed["unlocked_achievements"] = unlocked_achievements

    var write_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if write_file != null:
        write_file.store_string(JSON.stringify(parsed))
