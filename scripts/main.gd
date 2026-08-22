extends Control

const SAVE_PATH := "user://save.json"
const APP_VERSION := "1.0.0"
const TARGET := 100.0
const STREAK_THRESHOLD := 99.900
const PERFECT_WINDOW := 0.005
const MAX_PARTICLES := 30

enum GameState { READY, RUNNING, RESULT }
enum AppScreen { MENU, GAME, LEADERBOARD, STATS, SETTINGS }

var screen: AppScreen = AppScreen.MENU
var state: GameState = GameState.READY
var game_paused := false
var meter_value := 0.0
var meter_phase := 0.0
var meter_speed := 2.45
var round_number := 1
var streak := 0
var best_streak := 0
var best_value := 0.0
var games_played := 0
var local_perfect_count := 0
var result_value := 0.0
var result_title := ""
var result_subtitle := ""
var pulse_time := 0.0
var shake_time := 0.0
var flash_alpha := 0.0
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var player_id := ""
var player_name := "PLAYER"
var leaderboard_mode := "hit"

@onready var leaderboard_service: Node = $LeaderboardService

var gameplay_layer: Control
var menu_layer: Control
var pause_layer: Control
var leaderboard_layer: Control
var stats_layer: Control
var settings_layer: Control

var title_label: Label
var percent_label: Label
var hint_label: Label
var best_label: Label
var streak_label: Label
var result_label: Label
var result_detail_label: Label
var footer_label: Label
var menu_best_label: Label
var menu_streak_label: Label
var stats_body_label: Label
var name_input: LineEdit
var settings_status_label: Label
var leaderboard_title_label: Label
var leaderboard_status_label: Label
var leaderboard_me_label: Label
var leaderboard_rows: VBoxContainer
var hit_tab_button: Button
var streak_tab_button: Button

func _ready() -> void:
    rng.randomize()
    _load_save()
    if player_id.is_empty():
        player_id = _make_uuid()
        _save()
    _build_ui()
    _connect_leaderboard_signals()
    _show_screen(AppScreen.MENU)
    set_process(true)
    queue_redraw()

func _connect_leaderboard_signals() -> void:
    leaderboard_service.leaderboard_loaded.connect(_on_leaderboard_loaded)
    leaderboard_service.leaderboard_failed.connect(_on_leaderboard_failed)
    leaderboard_service.score_submitted.connect(_on_score_submitted)
    leaderboard_service.score_submit_failed.connect(_on_score_submit_failed)
    leaderboard_service.name_saved.connect(_on_name_saved)
    leaderboard_service.name_save_failed.connect(_on_name_save_failed)

func _build_ui() -> void:
    gameplay_layer = _full_layer()
    menu_layer = _full_layer()
    pause_layer = _full_layer()
    leaderboard_layer = _full_layer()
    stats_layer = _full_layer()
    settings_layer = _full_layer()

    _build_game_ui()
    _build_menu_ui()
    _build_pause_ui()
    _build_leaderboard_ui()
    _build_stats_ui()
    _build_settings_ui()
    _refresh_labels()
    _refresh_menu_stats()
    _refresh_stats_screen()

func _full_layer() -> Control:
    var layer := Control.new()
    layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(layer)
    return layer

func _build_game_ui() -> void:
    title_label = _make_label("99.9%", 86, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title_label, Vector2(90, 135), Vector2(900, 120), gameplay_layer)
    title_label.modulate = Color(0.95, 0.97, 1.0)

    var tagline := _make_label("HOW CLOSE CAN YOU GET?", 27, HORIZONTAL_ALIGNMENT_CENTER)
    _place(tagline, Vector2(90, 258), Vector2(900, 52), gameplay_layer)
    tagline.modulate = Color(0.52, 0.57, 0.68)

    percent_label = _make_label("0.000%", 112, HORIZONTAL_ALIGNMENT_CENTER)
    _place(percent_label, Vector2(90, 590), Vector2(900, 150), gameplay_layer)
    percent_label.modulate = Color(0.97, 0.98, 1.0)

    streak_label = _make_label("STREAK  0", 30, HORIZONTAL_ALIGNMENT_LEFT)
    _place(streak_label, Vector2(115, 350), Vector2(400, 55), gameplay_layer)
    streak_label.modulate = Color(0.62, 0.67, 0.78)

    best_label = _make_label("BEST  0.000%", 30, HORIZONTAL_ALIGNMENT_RIGHT)
    _place(best_label, Vector2(565, 350), Vector2(400, 55), gameplay_layer)
    best_label.modulate = Color(0.62, 0.67, 0.78)

    result_label = _make_label("", 62, HORIZONTAL_ALIGNMENT_CENTER)
    _place(result_label, Vector2(90, 1010), Vector2(900, 90), gameplay_layer)

    result_detail_label = _make_label("", 30, HORIZONTAL_ALIGNMENT_CENTER)
    _place(result_detail_label, Vector2(100, 1100), Vector2(880, 130), gameplay_layer)
    result_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    result_detail_label.modulate = Color(0.66, 0.71, 0.80)

    hint_label = _make_label("TAP TO START", 40, HORIZONTAL_ALIGNMENT_CENTER)
    _place(hint_label, Vector2(120, 1370), Vector2(840, 80), gameplay_layer)
    hint_label.modulate = Color(0.88, 0.91, 1.0)

    footer_label = _make_label("Hit 99.900%+ to keep your streak", 25, HORIZONTAL_ALIGNMENT_CENTER)
    _place(footer_label, Vector2(90, 1690), Vector2(900, 60), gameplay_layer)
    footer_label.modulate = Color(0.38, 0.42, 0.52)

    var pause_button := _make_button("PAUSE", Vector2(150, 64))
    _place(pause_button, Vector2(895, 55), Vector2(150, 64), gameplay_layer)
    pause_button.pressed.connect(_pause_game)

func _build_menu_ui() -> void:
    var menu_title := _make_label("99.9%", 128, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_title, Vector2(90, 205), Vector2(900, 170), menu_layer)
    menu_title.modulate = Color(0.96, 0.98, 1.0)

    var menu_tagline := _make_label("ONE TAP. ONE CHANCE.", 30, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_tagline, Vector2(100, 385), Vector2(880, 55), menu_layer)
    menu_tagline.modulate = Color(0.52, 0.58, 0.70)

    menu_best_label = _make_label("BEST  0.000%", 32, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_best_label, Vector2(120, 515), Vector2(410, 70), menu_layer)
    menu_best_label.modulate = Color(0.72, 0.78, 0.90)

    menu_streak_label = _make_label("BEST STREAK  0", 32, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_streak_label, Vector2(550, 515), Vector2(410, 70), menu_layer)
    menu_streak_label.modulate = Color(0.72, 0.78, 0.90)

    var play := _make_button("PLAY", Vector2(760, 118), 42, true)
    _place(play, Vector2(160, 710), Vector2(760, 118), menu_layer)
    play.pressed.connect(_start_game_session)

    var leaderboard := _make_button("WORLD LEADERBOARD", Vector2(760, 96), 32)
    _place(leaderboard, Vector2(160, 860), Vector2(760, 96), menu_layer)
    leaderboard.pressed.connect(func() -> void: _open_leaderboard("hit"))

    var stats := _make_button("STATS", Vector2(760, 96), 32)
    _place(stats, Vector2(160, 980), Vector2(760, 96), menu_layer)
    stats.pressed.connect(func() -> void:
        _refresh_stats_screen()
        _show_screen(AppScreen.STATS)
    )

    var settings := _make_button("SETTINGS", Vector2(760, 96), 32)
    _place(settings, Vector2(160, 1100), Vector2(760, 96), menu_layer)
    settings.pressed.connect(func() -> void:
        name_input.text = player_name
        settings_status_label.text = ""
        _show_screen(AppScreen.SETTINGS)
    )

    var online := _make_label("GLOBAL RANKINGS · iOS + ANDROID", 24, HORIZONTAL_ALIGNMENT_CENTER)
    _place(online, Vector2(120, 1420), Vector2(840, 60), menu_layer)
    online.modulate = Color(0.37, 0.43, 0.54)

func _build_pause_ui() -> void:
    var shade := ColorRect.new()
    shade.color = Color(0.01, 0.015, 0.025, 0.90)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    pause_layer.add_child(shade)

    var paused := _make_label("PAUSED", 78, HORIZONTAL_ALIGNMENT_CENTER)
    _place(paused, Vector2(120, 430), Vector2(840, 110), pause_layer)

    var resume := _make_button("RESUME", Vector2(700, 105), 36, true)
    _place(resume, Vector2(190, 650), Vector2(700, 105), pause_layer)
    resume.pressed.connect(_resume_game)

    var restart := _make_button("RESTART RUN", Vector2(700, 96), 31)
    _place(restart, Vector2(190, 785), Vector2(700, 96), pause_layer)
    restart.pressed.connect(_restart_run)

    var home := _make_button("MAIN MENU", Vector2(700, 96), 31)
    _place(home, Vector2(190, 905), Vector2(700, 96), pause_layer)
    home.pressed.connect(_return_to_menu)

func _build_leaderboard_ui() -> void:
    leaderboard_title_label = _make_label("WORLD LEADERBOARD", 62, HORIZONTAL_ALIGNMENT_CENTER)
    _place(leaderboard_title_label, Vector2(100, 150), Vector2(880, 90), leaderboard_layer)

    var back := _make_button("BACK", Vector2(160, 62), 24)
    _place(back, Vector2(70, 55), Vector2(160, 62), leaderboard_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    hit_tab_button = _make_button("BEST HIT", Vector2(390, 82), 28)
    _place(hit_tab_button, Vector2(130, 300), Vector2(390, 82), leaderboard_layer)
    hit_tab_button.pressed.connect(func() -> void: _open_leaderboard("hit"))

    streak_tab_button = _make_button("LONGEST STREAK", Vector2(390, 82), 28)
    _place(streak_tab_button, Vector2(560, 300), Vector2(390, 82), leaderboard_layer)
    streak_tab_button.pressed.connect(func() -> void: _open_leaderboard("streak"))

    leaderboard_status_label = _make_label("LOADING...", 27, HORIZONTAL_ALIGNMENT_CENTER)
    _place(leaderboard_status_label, Vector2(120, 405), Vector2(840, 55), leaderboard_layer)
    leaderboard_status_label.modulate = Color(0.50, 0.56, 0.68)

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(105, 480)
    scroll.size = Vector2(870, 980)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    leaderboard_layer.add_child(scroll)

    leaderboard_rows = VBoxContainer.new()
    leaderboard_rows.custom_minimum_size = Vector2(840, 0)
    leaderboard_rows.add_theme_constant_override("separation", 12)
    scroll.add_child(leaderboard_rows)

    leaderboard_me_label = _make_label("", 27, HORIZONTAL_ALIGNMENT_CENTER)
    _place(leaderboard_me_label, Vector2(110, 1490), Vector2(860, 95), leaderboard_layer)
    leaderboard_me_label.modulate = Color(0.65, 0.92, 1.0)

    var refresh := _make_button("REFRESH", Vector2(420, 82), 27)
    _place(refresh, Vector2(330, 1635), Vector2(420, 82), leaderboard_layer)
    refresh.pressed.connect(func() -> void: _open_leaderboard(leaderboard_mode))

func _build_stats_ui() -> void:
    var title := _make_label("YOUR STATS", 70, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 180), Vector2(880, 100), stats_layer)

    var back := _make_button("BACK", Vector2(160, 62), 24)
    _place(back, Vector2(70, 55), Vector2(160, 62), stats_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    stats_body_label = _make_label("", 38, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_body_label, Vector2(120, 430), Vector2(840, 750), stats_layer)
    stats_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    stats_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var leaderboard := _make_button("OPEN WORLD LEADERBOARD", Vector2(700, 96), 29)
    _place(leaderboard, Vector2(190, 1330), Vector2(700, 96), stats_layer)
    leaderboard.pressed.connect(func() -> void: _open_leaderboard("hit"))

func _build_settings_ui() -> void:
    var title := _make_label("SETTINGS", 70, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 180), Vector2(880, 100), settings_layer)

    var back := _make_button("BACK", Vector2(160, 62), 24)
    _place(back, Vector2(70, 55), Vector2(160, 62), settings_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    var name_label := _make_label("PLAYER NAME", 30, HORIZONTAL_ALIGNMENT_LEFT)
    _place(name_label, Vector2(165, 470), Vector2(750, 60), settings_layer)
    name_label.modulate = Color(0.60, 0.67, 0.80)

    name_input = LineEdit.new()
    name_input.text = player_name
    name_input.placeholder_text = "PLAYER"
    name_input.max_length = 18
    name_input.add_theme_font_size_override("font_size", 34)
    name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _place(name_input, Vector2(165, 550), Vector2(750, 90), settings_layer)

    var save_name := _make_button("SAVE NAME", Vector2(750, 96), 30, true)
    _place(save_name, Vector2(165, 675), Vector2(750, 96), settings_layer)
    save_name.pressed.connect(_save_player_name)

    settings_status_label = _make_label("", 27, HORIZONTAL_ALIGNMENT_CENTER)
    _place(settings_status_label, Vector2(150, 800), Vector2(780, 110), settings_layer)
    settings_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var note := _make_label("2–18 characters · A–Z · 0–9 · space · _ · -\nUsed on the worldwide leaderboard.", 25, HORIZONTAL_ALIGNMENT_CENTER)
    _place(note, Vector2(140, 980), Vector2(800, 140), settings_layer)
    note.modulate = Color(0.42, 0.48, 0.59)

func _make_label(text_value: String, font_size: int, alignment: HorizontalAlignment) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.horizontal_alignment = alignment
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label

func _make_button(text_value: String, minimum: Vector2, font_size: int = 30, accent: bool = false) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = minimum
    button.add_theme_font_size_override("font_size", font_size)
    button.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_stylebox_override("normal", _rounded_box(Color(0.11, 0.135, 0.20) if not accent else Color(0.16, 0.52, 0.85), 24))
    button.add_theme_stylebox_override("hover", _rounded_box(Color(0.15, 0.18, 0.27) if not accent else Color(0.20, 0.61, 0.96), 24))
    button.add_theme_stylebox_override("pressed", _rounded_box(Color(0.075, 0.09, 0.14) if not accent else Color(0.12, 0.43, 0.72), 24))
    return button

func _place(control: Control, position: Vector2, control_size: Vector2, parent: Control) -> void:
    control.position = position
    control.size = control_size
    parent.add_child(control)

func _process(delta: float) -> void:
    pulse_time += delta
    if screen == AppScreen.GAME and not game_paused:
        flash_alpha = maxf(0.0, flash_alpha - delta * 2.7)
        shake_time = maxf(0.0, shake_time - delta)

        if state == GameState.RUNNING:
            meter_phase = fmod(meter_phase + meter_speed * delta, TAU)
            meter_value = 50.0 - 50.0 * cos(meter_phase)
            percent_label.text = _format_percent(meter_value)

        _update_particles(delta)
        hint_label.modulate.a = 0.72 + sin(pulse_time * 4.0) * 0.18
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if screen != AppScreen.GAME or game_paused:
        return

    var tapped := false
    if event is InputEventScreenTouch:
        tapped = event.pressed
    elif event is InputEventMouseButton:
        tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT

    if not tapped:
        return

    get_viewport().set_input_as_handled()
    match state:
        GameState.READY:
            _start_round()
        GameState.RUNNING:
            _stop_round()
        GameState.RESULT:
            _next_round()

func _show_screen(target: AppScreen) -> void:
    screen = target
    gameplay_layer.visible = target == AppScreen.GAME
    menu_layer.visible = target == AppScreen.MENU
    leaderboard_layer.visible = target == AppScreen.LEADERBOARD
    stats_layer.visible = target == AppScreen.STATS
    settings_layer.visible = target == AppScreen.SETTINGS
    pause_layer.visible = target == AppScreen.GAME and game_paused
    if target == AppScreen.MENU:
        _refresh_menu_stats()
    queue_redraw()

func _start_game_session() -> void:
    streak = 0
    round_number = 1
    game_paused = false
    _reset_to_ready()
    _show_screen(AppScreen.GAME)

func _reset_to_ready() -> void:
    state = GameState.READY
    meter_value = 0.0
    meter_phase = 0.0
    result_value = 0.0
    particles.clear()
    result_label.text = ""
    result_detail_label.text = ""
    percent_label.text = _format_percent(0.0)
    hint_label.text = "TAP TO START"
    _refresh_labels()

func _pause_game() -> void:
    if screen != AppScreen.GAME or game_paused:
        return
    game_paused = true
    pause_layer.visible = true

func _resume_game() -> void:
    game_paused = false
    pause_layer.visible = false

func _restart_run() -> void:
    game_paused = false
    pause_layer.visible = false
    streak = 0
    round_number = 1
    _reset_to_ready()

func _return_to_menu() -> void:
    game_paused = false
    streak = 0
    _reset_to_ready()
    _show_screen(AppScreen.MENU)

func _start_round() -> void:
    state = GameState.RUNNING
    result_label.text = ""
    result_detail_label.text = ""
    hint_label.text = "TAP TO STOP"
    meter_value = 0.0
    meter_phase = 0.0
    meter_speed = _speed_for_round()
    percent_label.text = _format_percent(meter_value)

func _stop_round() -> void:
    state = GameState.RESULT
    games_played += 1
    result_value = meter_value

    if TARGET - result_value <= PERFECT_WINDOW:
        result_value = TARGET

    if result_value > best_value:
        best_value = result_value

    var kept_streak := result_value >= STREAK_THRESHOLD
    if kept_streak:
        streak += 1
        best_streak = maxi(best_streak, streak)
    else:
        streak = 0

    if result_value >= TARGET:
        local_perfect_count += 1

    _evaluate_result(result_value)
    _spawn_result_particles(result_value)
    _save()
    _refresh_labels()
    _refresh_menu_stats()
    hint_label.text = "TAP FOR NEXT ROUND"
    percent_label.text = _format_percent(result_value)

    var score_milli := clampi(int(round(result_value * 1000.0)), 0, 100000)
    leaderboard_service.submit_score(player_id, score_milli, _platform_name(), APP_VERSION)

func _next_round() -> void:
    round_number += 1
    _start_round()

func _speed_for_round() -> float:
    var streak_boost := minf(float(streak) * 0.12, 1.50)
    var round_variation := rng.randf_range(-0.05, 0.08)
    return 2.45 + streak_boost + round_variation

func _evaluate_result(value: float) -> void:
    var miss := TARGET - value
    flash_alpha = 0.48

    if value >= TARGET:
        result_title = "PERFECT."
        result_subtitle = "You hit 100.000%. That's disgusting."
        result_label.modulate = Color(1.0, 0.86, 0.35)
        shake_time = 0.2
    elif value >= 99.990:
        result_title = "ABSURDLY CLOSE"
        result_subtitle = "Only %.3f%% away from perfect." % miss
        result_label.modulate = Color(0.65, 0.95, 1.0)
    elif value >= STREAK_THRESHOLD:
        result_title = "99.9 CLUB"
        result_subtitle = "Streak saved. Now do it faster."
        result_label.modulate = Color(0.55, 1.0, 0.72)
    elif value >= 99.000:
        result_title = "SO CLOSE"
        result_subtitle = "Missed the streak by %.3f%%." % (STREAK_THRESHOLD - value)
        result_label.modulate = Color(1.0, 0.72, 0.40)
        shake_time = 0.14
    else:
        result_title = "NOPE."
        result_subtitle = "You were %.3f%% away. Again." % miss
        result_label.modulate = Color(1.0, 0.46, 0.50)
        shake_time = 0.18

    result_label.text = result_title
    result_detail_label.text = result_subtitle

func _open_leaderboard(mode: String) -> void:
    leaderboard_mode = "streak" if mode == "streak" else "hit"
    _show_screen(AppScreen.LEADERBOARD)
    leaderboard_status_label.text = "LOADING..."
    leaderboard_me_label.text = ""
    _clear_leaderboard_rows()
    _refresh_leaderboard_tabs()
    leaderboard_service.load_leaderboard(leaderboard_mode, player_id, 25)

func _refresh_leaderboard_tabs() -> void:
    hit_tab_button.modulate = Color.WHITE if leaderboard_mode == "hit" else Color(0.62, 0.66, 0.75)
    streak_tab_button.modulate = Color.WHITE if leaderboard_mode == "streak" else Color(0.62, 0.66, 0.75)

func _on_leaderboard_loaded(mode: String, top: Array, me: Variant) -> void:
    if screen != AppScreen.LEADERBOARD or mode != leaderboard_mode:
        return
    _clear_leaderboard_rows()
    leaderboard_status_label.text = "BEST HIT · GLOBAL" if mode == "hit" else "LONGEST STREAK · GLOBAL"

    if top.is_empty():
        var empty := _make_label("NO SCORES YET — BE THE FIRST.", 28, HORIZONTAL_ALIGNMENT_CENTER)
        empty.custom_minimum_size = Vector2(840, 100)
        leaderboard_rows.add_child(empty)
    else:
        for raw_row in top:
            if typeof(raw_row) == TYPE_DICTIONARY:
                _add_leaderboard_row(raw_row, mode)

    if typeof(me) == TYPE_DICTIONARY:
        var mine: Dictionary = me
        var rank := int(mine.get("rank", 0))
        var hit := float(int(mine.get("best_hit_milli", 0))) / 1000.0
        var best_server_streak := int(mine.get("best_streak", 0))
        leaderboard_me_label.text = "YOU  #%d   %.3f%%   ·   STREAK %d" % [rank, hit, best_server_streak]
    else:
        leaderboard_me_label.text = "PLAY A ROUND TO ENTER THE WORLD RANKING"

func _add_leaderboard_row(row: Dictionary, mode: String) -> void:
    var line := HBoxContainer.new()
    line.custom_minimum_size = Vector2(840, 66)
    line.add_theme_constant_override("separation", 10)

    var rank_label := _make_label("#%d" % int(row.get("rank", 0)), 27, HORIZONTAL_ALIGNMENT_LEFT)
    rank_label.custom_minimum_size = Vector2(100, 66)
    line.add_child(rank_label)

    var name_label := _make_label(str(row.get("display_name", "PLAYER")), 27, HORIZONTAL_ALIGNMENT_LEFT)
    name_label.custom_minimum_size = Vector2(370, 66)
    if str(row.get("player_id", "")) == player_id:
        name_label.modulate = Color(0.55, 1.0, 0.72)
    line.add_child(name_label)

    var hit := float(int(row.get("best_hit_milli", 0))) / 1000.0
    var server_streak := int(row.get("best_streak", 0))
    var value_text := "%.3f%%  · S%d" % [hit, server_streak] if mode == "hit" else "S%d  · %.3f%%" % [server_streak, hit]
    var value_label := _make_label(value_text, 27, HORIZONTAL_ALIGNMENT_RIGHT)
    value_label.custom_minimum_size = Vector2(340, 66)
    line.add_child(value_label)

    leaderboard_rows.add_child(line)

func _clear_leaderboard_rows() -> void:
    for child in leaderboard_rows.get_children():
        child.queue_free()

func _on_leaderboard_failed(message: String) -> void:
    if screen == AppScreen.LEADERBOARD:
        leaderboard_status_label.text = message.to_upper()
        leaderboard_me_label.text = "CHECK CONNECTION AND TAP REFRESH"

func _on_score_submitted(_player: Dictionary) -> void:
    pass

func _on_score_submit_failed(_message: String) -> void:
    # Gameplay must never be blocked by a leaderboard/network failure.
    pass

func _save_player_name() -> void:
    var requested := name_input.text.strip_edges().to_upper()
    if requested.length() < 2 or requested.length() > 18:
        settings_status_label.text = "NAME MUST BE 2–18 CHARACTERS"
        settings_status_label.modulate = Color(1.0, 0.55, 0.55)
        return
    var regex := RegEx.new()
    regex.compile("^[A-Z0-9 _-]+$")
    if regex.search(requested) == null:
        settings_status_label.text = "USE ONLY A–Z, 0–9, SPACE, _ OR -"
        settings_status_label.modulate = Color(1.0, 0.55, 0.55)
        return
    settings_status_label.text = "SAVING..."
    settings_status_label.modulate = Color(0.60, 0.67, 0.80)
    leaderboard_service.save_name(player_id, requested)

func _on_name_saved(player: Dictionary) -> void:
    player_name = str(player.get("display_name", name_input.text.strip_edges().to_upper()))
    name_input.text = player_name
    settings_status_label.text = "SAVED · %s" % player_name
    settings_status_label.modulate = Color(0.55, 1.0, 0.72)
    _save()

func _on_name_save_failed(message: String) -> void:
    settings_status_label.text = message.to_upper()
    settings_status_label.modulate = Color(1.0, 0.55, 0.55)

func _refresh_labels() -> void:
    streak_label.text = "STREAK  %d" % streak
    best_label.text = "BEST  %s" % _format_percent(best_value)

func _refresh_menu_stats() -> void:
    if menu_best_label != null:
        menu_best_label.text = "BEST  %s" % _format_percent(best_value)
    if menu_streak_label != null:
        menu_streak_label.text = "BEST STREAK  %d" % best_streak

func _refresh_stats_screen() -> void:
    if stats_body_label == null:
        return
    stats_body_label.text = "BEST HIT\n%s\n\nLONGEST STREAK\n%d\n\nROUNDS PLAYED\n%d\n\nPERFECT 100.000%%\n%d\n\nPLAYER\n%s" % [
        _format_percent(best_value),
        best_streak,
        games_played,
        local_perfect_count,
        player_name,
    ]

func _format_percent(value: float) -> String:
    return "%.3f%%" % clampf(value, 0.0, TARGET)

func _spawn_result_particles(value: float) -> void:
    particles.clear()
    var amount := 8
    if value >= STREAK_THRESHOLD:
        amount = 18
    if value >= TARGET:
        amount = MAX_PARTICLES

    for i in range(amount):
        particles.append({
            "p": Vector2(rng.randf_range(280.0, 800.0), rng.randf_range(820.0, 980.0)),
            "v": Vector2(rng.randf_range(-170.0, 170.0), rng.randf_range(-310.0, -120.0)),
            "life": rng.randf_range(0.55, 1.15),
            "max_life": 1.15,
            "size": rng.randf_range(5.0, 12.0),
        })

func _update_particles(delta: float) -> void:
    for particle in particles:
        particle["life"] = float(particle["life"]) - delta
        particle["v"] = Vector2(particle["v"]) + Vector2(0.0, 520.0) * delta
        particle["p"] = Vector2(particle["p"]) + Vector2(particle["v"]) * delta

    for i in range(particles.size() - 1, -1, -1):
        if float(particles[i]["life"]) <= 0.0:
            particles.remove_at(i)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.025), true)

    if screen != AppScreen.GAME:
        draw_circle(Vector2(540, 650), 520.0, Color(0.055, 0.070, 0.12, 0.36))
        draw_circle(Vector2(540, 680), 300.0, Color(0.07, 0.11, 0.19, 0.28))
        return

    var shake := Vector2.ZERO
    if shake_time > 0.0 and not game_paused:
        shake = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 5.0))

    draw_circle(Vector2(540, 710) + shake, 540.0, Color(0.055, 0.070, 0.12, 0.45))
    draw_circle(Vector2(540, 720) + shake, 340.0, Color(0.07, 0.11, 0.19, 0.40))

    var meter_rect := Rect2(Vector2(115, 805) + shake, Vector2(850, 110))
    draw_style_box(_rounded_box(Color(0.075, 0.085, 0.12, 1.0), 28), meter_rect)

    var inner := Rect2(meter_rect.position + Vector2(13, 13), Vector2(meter_rect.size.x - 26, meter_rect.size.y - 26))
    draw_style_box(_rounded_box(Color(0.025, 0.030, 0.048, 1.0), 20), inner)

    var zone_width := maxf(8.0, inner.size.x * ((100.0 - STREAK_THRESHOLD) / 100.0) * 18.0)
    var zone := Rect2(Vector2(inner.end.x - zone_width, inner.position.y), Vector2(zone_width, inner.size.y))
    draw_rect(zone, Color(0.22, 0.86, 0.62, 0.28), true)

    var fill_width := inner.size.x * (meter_value / TARGET)
    if state == GameState.RESULT:
        fill_width = inner.size.x * (result_value / TARGET)
    if fill_width > 0.0:
        var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
        draw_style_box(_rounded_box(_meter_color(state == GameState.RESULT), 20), fill_rect)

    draw_line(Vector2(inner.end.x, inner.position.y - 26), Vector2(inner.end.x, inner.end.y + 26), Color(1.0, 0.85, 0.35), 5.0)
    var cursor_value := result_value if state == GameState.RESULT else meter_value
    var cursor_x := inner.position.x + inner.size.x * (cursor_value / TARGET)
    draw_line(Vector2(cursor_x, inner.position.y - 16), Vector2(cursor_x, inner.end.y + 16), Color(1.0, 1.0, 1.0), 7.0)

    for tick in range(0, 101, 10):
        var x := inner.position.x + inner.size.x * (float(tick) / 100.0)
        draw_line(Vector2(x, inner.end.y + 8), Vector2(x, inner.end.y + (24 if tick % 50 == 0 else 17)), Color(0.35, 0.39, 0.48, 0.55), 2.0)

    for particle in particles:
        var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
        draw_circle(Vector2(particle["p"]), float(particle["size"]), Color(0.65, 0.92, 1.0, life_ratio))

    if flash_alpha > 0.0 and not game_paused:
        draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, flash_alpha * 0.12), true)

func _meter_color(is_result: bool) -> Color:
    var value := result_value if is_result else meter_value
    if value >= STREAK_THRESHOLD:
        return Color(0.20, 0.88, 0.60)
    if value >= 95.0:
        return Color(0.95, 0.64, 0.24)
    return Color(0.30, 0.52, 1.0)

func _rounded_box(color: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    return style

func _platform_name() -> String:
    var os_name := OS.get_name().to_lower()
    if os_name == "ios":
        return "ios"
    if os_name == "android":
        return "android"
    return "unknown"

func _load_save() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    best_value = float(parsed.get("best_value", 0.0))
    best_streak = int(parsed.get("best_streak", 0))
    games_played = int(parsed.get("games_played", 0))
    local_perfect_count = int(parsed.get("perfect_count", 0))
    player_id = str(parsed.get("player_id", ""))
    player_name = str(parsed.get("player_name", "PLAYER"))

func _save() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        return
    var payload := {
        "best_value": best_value,
        "best_streak": best_streak,
        "games_played": games_played,
        "perfect_count": local_perfect_count,
        "player_id": player_id,
        "player_name": player_name,
    }
    file.store_string(JSON.stringify(payload))

func _make_uuid() -> String:
    var bytes := Crypto.new().generate_random_bytes(16)
    if bytes.size() != 16:
        return "%08x-%04x-4%03x-a%03x-%012x" % [rng.randi(), rng.randi() & 0xffff, rng.randi() & 0xfff, rng.randi() & 0xfff, rng.randi()]
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    var hex := bytes.hex_encode()
    return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
