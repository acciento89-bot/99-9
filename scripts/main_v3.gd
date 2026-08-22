extends Control

const SAVE_PATH := "user://save.json"
const APP_VERSION := "1.0.0"
const TARGET := 100.0
const STREAK_THRESHOLD := 99.900
const PERFECT_WINDOW := 0.005
const MAX_PARTICLES := 30
const THEME_IDS := ["midnight", "neon", "gold", "aurora"]

enum GameState { READY, RUNNING, RESULT }
enum AppScreen { MENU, GAME, LEADERBOARD, STATS, SETTINGS, THEMES }

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

var selected_theme_id := "midnight"
var active_theme_id := "midnight"
var preview_theme_id := "midnight"
var owned_themes: Array[String] = ["midnight"]

@onready var leaderboard_service: Node = $LeaderboardService

var gameplay_layer: Control
var menu_layer: Control
var pause_layer: Control
var leaderboard_layer: Control
var stats_layer: Control
var settings_layer: Control
var themes_layer: Control

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
var menu_theme_label: Label

var stats_best_value_label: Label
var stats_streak_value_label: Label
var stats_rounds_value_label: Label
var stats_perfect_value_label: Label
var stats_player_label: Label

var name_input: LineEdit
var settings_status_label: Label

var leaderboard_status_label: Label
var leaderboard_me_label: Label
var leaderboard_rows: VBoxContainer
var hit_tab_button: Button
var streak_tab_button: Button

var theme_preview_title: Label
var theme_preview_detail: Label
var theme_action_button: Button
var theme_status_label: Label
var theme_card_buttons: Dictionary = {}

var themed_buttons: Array[Button] = []
var themed_panels: Array[Panel] = []
var muted_labels: Array[Label] = []

func _ready() -> void:
    rng.randomize()
    _load_save()
    if player_id.is_empty():
        player_id = _make_uuid()
        _save()
    active_theme_id = selected_theme_id
    preview_theme_id = selected_theme_id
    _build_ui()
    _connect_leaderboard_signals()
    _apply_theme_to_controls()
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
    themes_layer = _full_layer()

    _build_game_ui()
    _build_menu_ui()
    _build_pause_ui()
    _build_leaderboard_ui()
    _build_stats_ui()
    _build_settings_ui()
    _build_themes_ui()

    _refresh_labels()
    _refresh_menu_stats()
    _refresh_stats_screen()
    _refresh_theme_screen()

func _full_layer() -> Control:
    var layer := Control.new()
    layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(layer)
    return layer

func _build_game_ui() -> void:
    title_label = _make_label("99.9%", 86, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title_label, Vector2(90, 135), Vector2(900, 120), gameplay_layer)

    var tagline := _make_muted_label("HOW CLOSE CAN YOU GET?", 27, HORIZONTAL_ALIGNMENT_CENTER)
    _place(tagline, Vector2(90, 258), Vector2(900, 52), gameplay_layer)

    percent_label = _make_label("0.000%", 112, HORIZONTAL_ALIGNMENT_CENTER)
    _place(percent_label, Vector2(90, 590), Vector2(900, 150), gameplay_layer)

    streak_label = _make_muted_label("STREAK  0", 30, HORIZONTAL_ALIGNMENT_LEFT)
    _place(streak_label, Vector2(115, 350), Vector2(400, 55), gameplay_layer)

    best_label = _make_muted_label("BEST  0.000%", 30, HORIZONTAL_ALIGNMENT_RIGHT)
    _place(best_label, Vector2(565, 350), Vector2(400, 55), gameplay_layer)

    result_label = _make_label("", 62, HORIZONTAL_ALIGNMENT_CENTER)
    _place(result_label, Vector2(90, 1010), Vector2(900, 90), gameplay_layer)

    result_detail_label = _make_muted_label("", 30, HORIZONTAL_ALIGNMENT_CENTER)
    _place(result_detail_label, Vector2(100, 1100), Vector2(880, 130), gameplay_layer)
    result_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    hint_label = _make_label("TAP TO START", 40, HORIZONTAL_ALIGNMENT_CENTER)
    _place(hint_label, Vector2(120, 1370), Vector2(840, 80), gameplay_layer)

    footer_label = _make_muted_label("Hit 99.900%+ to keep your streak", 25, HORIZONTAL_ALIGNMENT_CENTER)
    _place(footer_label, Vector2(90, 1690), Vector2(900, 60), gameplay_layer)

    var pause_button := _make_button("II", Vector2(92, 72), 30, "ghost")
    _place(pause_button, Vector2(930, 55), Vector2(92, 72), gameplay_layer)
    pause_button.pressed.connect(_pause_game)

func _build_menu_ui() -> void:
    var badge := _make_panel("soft")
    _place(badge, Vector2(330, 160), Vector2(420, 54), menu_layer)
    var badge_text := _make_muted_label("GLOBAL PRECISION CHALLENGE", 19, HORIZONTAL_ALIGNMENT_CENTER)
    _place(badge_text, Vector2(0, 0), Vector2(420, 54), badge)

    var menu_title := _make_label("99.9%", 132, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_title, Vector2(90, 230), Vector2(900, 165), menu_layer)

    var menu_tagline := _make_muted_label("ONE TAP. ONE CHANCE.", 29, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_tagline, Vector2(100, 390), Vector2(880, 52), menu_layer)

    var score_card := _make_panel("card")
    _place(score_card, Vector2(130, 505), Vector2(820, 190), menu_layer)

    var best_caption := _make_muted_label("PERSONAL BEST", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(best_caption, Vector2(25, 22), Vector2(365, 42), score_card)
    menu_best_label = _make_label("99.993%", 40, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_best_label, Vector2(25, 62), Vector2(365, 72), score_card)

    var divider := ColorRect.new()
    divider.color = Color(1, 1, 1, 0.08)
    _place(divider, Vector2(410, 36), Vector2(2, 118), score_card)

    var streak_caption := _make_muted_label("LONGEST STREAK", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(streak_caption, Vector2(430, 22), Vector2(365, 42), score_card)
    menu_streak_label = _make_label("2", 40, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_streak_label, Vector2(430, 62), Vector2(365, 72), score_card)

    var play := _make_button("PLAY NOW", Vector2(820, 124), 42, "accent")
    _place(play, Vector2(130, 750), Vector2(820, 124), menu_layer)
    play.pressed.connect(_start_game_session)

    var leaderboard := _make_button("WORLD RANKING", Vector2(390, 104), 28, "secondary")
    _place(leaderboard, Vector2(130, 915), Vector2(390, 104), menu_layer)
    leaderboard.pressed.connect(func() -> void: _open_leaderboard("hit"))

    var stats := _make_button("MY STATS", Vector2(390, 104), 28, "secondary")
    _place(stats, Vector2(560, 915), Vector2(390, 104), menu_layer)
    stats.pressed.connect(func() -> void:
        _refresh_stats_screen()
        _show_screen(AppScreen.STATS)
    )

    var designs := _make_button("DESIGNS", Vector2(390, 104), 28, "secondary")
    _place(designs, Vector2(130, 1045), Vector2(390, 104), menu_layer)
    designs.pressed.connect(_open_themes)

    var settings := _make_button("SETTINGS", Vector2(390, 104), 28, "secondary")
    _place(settings, Vector2(560, 1045), Vector2(390, 104), menu_layer)
    settings.pressed.connect(_open_settings)

    menu_theme_label = _make_muted_label("THEME · MIDNIGHT", 22, HORIZONTAL_ALIGNMENT_CENTER)
    _place(menu_theme_label, Vector2(140, 1260), Vector2(800, 55), menu_layer)

    var online := _make_muted_label("GLOBAL RANKINGS · iOS + ANDROID", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(online, Vector2(120, 1470), Vector2(840, 55), menu_layer)

func _build_pause_ui() -> void:
    var shade := ColorRect.new()
    shade.color = Color(0.0, 0.0, 0.0, 0.76)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    pause_layer.add_child(shade)

    var panel := _make_panel("card")
    _place(panel, Vector2(155, 430), Vector2(770, 650), pause_layer)

    var eyebrow := _make_muted_label("RUN PAUSED", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(70, 55), Vector2(630, 45), panel)

    var paused := _make_label("PAUSED", 72, HORIZONTAL_ALIGNMENT_CENTER)
    _place(paused, Vector2(70, 105), Vector2(630, 100), panel)

    var resume := _make_button("RESUME", Vector2(610, 100), 34, "accent")
    _place(resume, Vector2(80, 260), Vector2(610, 100), panel)
    resume.pressed.connect(_resume_game)

    var restart := _make_button("RESTART RUN", Vector2(610, 88), 28, "secondary")
    _place(restart, Vector2(80, 390), Vector2(610, 88), panel)
    restart.pressed.connect(_restart_run)

    var home := _make_button("MAIN MENU", Vector2(610, 88), 28, "ghost")
    _place(home, Vector2(80, 500), Vector2(610, 88), panel)
    home.pressed.connect(_return_to_menu)

func _build_leaderboard_ui() -> void:
    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), leaderboard_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    var eyebrow := _make_muted_label("GLOBAL · iOS + ANDROID", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 135), Vector2(760, 40), leaderboard_layer)

    var title := _make_label("WORLD RANKING", 60, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 175), Vector2(880, 90), leaderboard_layer)

    hit_tab_button = _make_button("BEST HIT", Vector2(390, 82), 27, "secondary")
    _place(hit_tab_button, Vector2(130, 315), Vector2(390, 82), leaderboard_layer)
    hit_tab_button.pressed.connect(func() -> void: _open_leaderboard("hit"))

    streak_tab_button = _make_button("LONGEST STREAK", Vector2(390, 82), 27, "secondary")
    _place(streak_tab_button, Vector2(560, 315), Vector2(390, 82), leaderboard_layer)
    streak_tab_button.pressed.connect(func() -> void: _open_leaderboard("streak"))

    leaderboard_status_label = _make_muted_label("LOADING...", 24, HORIZONTAL_ALIGNMENT_CENTER)
    _place(leaderboard_status_label, Vector2(120, 420), Vector2(840, 48), leaderboard_layer)

    var list_panel := _make_panel("soft")
    _place(list_panel, Vector2(95, 490), Vector2(890, 960), leaderboard_layer)

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(25, 25)
    scroll.size = Vector2(840, 910)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    list_panel.add_child(scroll)

    leaderboard_rows = VBoxContainer.new()
    leaderboard_rows.custom_minimum_size = Vector2(820, 0)
    leaderboard_rows.add_theme_constant_override("separation", 12)
    scroll.add_child(leaderboard_rows)

    leaderboard_me_label = _make_label("", 25, HORIZONTAL_ALIGNMENT_CENTER)
    _place(leaderboard_me_label, Vector2(110, 1480), Vector2(860, 92), leaderboard_layer)

    var refresh := _make_button("REFRESH", Vector2(420, 82), 25, "secondary")
    _place(refresh, Vector2(330, 1625), Vector2(420, 82), leaderboard_layer)
    refresh.pressed.connect(func() -> void: _open_leaderboard(leaderboard_mode))

func _build_stats_ui() -> void:
    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), stats_layer)
    back.pressed.connect(func() -> void: _show_screen(AppScreen.MENU))

    var eyebrow := _make_muted_label("PERSONAL RECORDS", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 145), Vector2(760, 40), stats_layer)

    var title := _make_label("YOUR STATS", 66, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 190), Vector2(880, 95), stats_layer)

    var card_a := _make_panel("card")
    _place(card_a, Vector2(130, 360), Vector2(390, 230), stats_layer)
    var cap_a := _make_muted_label("BEST HIT", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(cap_a, Vector2(30, 35), Vector2(330, 45), card_a)
    stats_best_value_label = _make_label("0.000%", 44, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_best_value_label, Vector2(20, 90), Vector2(350, 85), card_a)

    var card_b := _make_panel("card")
    _place(card_b, Vector2(560, 360), Vector2(390, 230), stats_layer)
    var cap_b := _make_muted_label("LONGEST STREAK", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(cap_b, Vector2(25, 35), Vector2(340, 45), card_b)
    stats_streak_value_label = _make_label("0", 44, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_streak_value_label, Vector2(20, 90), Vector2(350, 85), card_b)

    var card_c := _make_panel("card")
    _place(card_c, Vector2(130, 625), Vector2(390, 230), stats_layer)
    var cap_c := _make_muted_label("ROUNDS PLAYED", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(cap_c, Vector2(25, 35), Vector2(340, 45), card_c)
    stats_rounds_value_label = _make_label("0", 44, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_rounds_value_label, Vector2(20, 90), Vector2(350, 85), card_c)

    var card_d := _make_panel("card")
    _place(card_d, Vector2(560, 625), Vector2(390, 230), stats_layer)
    var cap_d := _make_muted_label("PERFECT HITS", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(cap_d, Vector2(25, 35), Vector2(340, 45), card_d)
    stats_perfect_value_label = _make_label("0", 44, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_perfect_value_label, Vector2(20, 90), Vector2(350, 85), card_d)

    var player_card := _make_panel("soft")
    _place(player_card, Vector2(130, 915), Vector2(820, 180), stats_layer)
    var player_cap := _make_muted_label("PLAYER", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(player_cap, Vector2(30, 30), Vector2(760, 40), player_card)
    stats_player_label = _make_label(player_name, 38, HORIZONTAL_ALIGNMENT_CENTER)
    _place(stats_player_label, Vector2(30, 75), Vector2(760, 68), player_card)

    var leaderboard := _make_button("OPEN WORLD RANKING", Vector2(820, 100), 29, "secondary")
    _place(leaderboard, Vector2(130, 1200), Vector2(820, 100), stats_layer)
    leaderboard.pressed.connect(func() -> void: _open_leaderboard("hit"))

func _build_settings_ui() -> void:
    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), settings_layer)
    back.pressed.connect(_close_settings)

    var eyebrow := _make_muted_label("PROFILE & APP", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 145), Vector2(760, 40), settings_layer)

    var title := _make_label("SETTINGS", 66, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 190), Vector2(880, 95), settings_layer)

    var profile_panel := _make_panel("card")
    _place(profile_panel, Vector2(130, 380), Vector2(820, 500), settings_layer)

    var name_label := _make_muted_label("PLAYER NAME", 22, HORIZONTAL_ALIGNMENT_LEFT)
    _place(name_label, Vector2(50, 45), Vector2(720, 48), profile_panel)

    var tap_hint := _make_muted_label("Tap the field below to edit", 19, HORIZONTAL_ALIGNMENT_RIGHT)
    _place(tap_hint, Vector2(350, 45), Vector2(420, 48), profile_panel)

    name_input = LineEdit.new()
    name_input.name = "PlayerNameInput"
    name_input.text = player_name
    name_input.placeholder_text = "PLAYER"
    name_input.max_length = 18
    name_input.add_theme_font_size_override("font_size", 34)
    name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_input.editable = true
    name_input.focus_mode = Control.FOCUS_ALL
    name_input.mouse_filter = Control.MOUSE_FILTER_STOP
    name_input.virtual_keyboard_enabled = true
    name_input.select_all_on_focus = true
    name_input.caret_blink = true
    name_input.context_menu_enabled = true
    name_input.text_submitted.connect(func(_submitted: String) -> void: _save_player_name())
    name_input.focus_entered.connect(_on_name_focus_entered)
    name_input.focus_exited.connect(_on_name_focus_exited)
    name_input.gui_input.connect(_on_name_input_gui_input)
    _place(name_input, Vector2(50, 115), Vector2(720, 100), profile_panel)

    var save_name := _make_button("SAVE PLAYER NAME", Vector2(720, 96), 28, "accent")
    _place(save_name, Vector2(50, 245), Vector2(720, 96), profile_panel)
    save_name.pressed.connect(_save_player_name)

    settings_status_label = _make_muted_label("2–18 characters · A–Z · 0–9 · space · _ · -", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(settings_status_label, Vector2(40, 365), Vector2(740, 80), profile_panel)
    settings_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var design_panel := _make_panel("soft")
    _place(design_panel, Vector2(130, 930), Vector2(820, 225), settings_layer)
    var design_title := _make_label("DESIGNS", 31, HORIZONTAL_ALIGNMENT_LEFT)
    _place(design_title, Vector2(45, 35), Vector2(360, 55), design_panel)
    var design_desc := _make_muted_label("Change the look of the entire game.", 20, HORIZONTAL_ALIGNMENT_LEFT)
    _place(design_desc, Vector2(45, 92), Vector2(500, 48), design_panel)
    var open_designs := _make_button("OPEN", Vector2(210, 76), 23, "secondary")
    _place(open_designs, Vector2(565, 72), Vector2(210, 76), design_panel)
    open_designs.pressed.connect(_open_themes)

func _build_themes_ui() -> void:
    var back := _make_button("BACK", Vector2(160, 62), 23, "ghost")
    _place(back, Vector2(70, 55), Vector2(160, 62), themes_layer)
    back.pressed.connect(_close_themes)

    var eyebrow := _make_muted_label("CUSTOMIZE YOUR RUN", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(eyebrow, Vector2(160, 125), Vector2(760, 40), themes_layer)

    var title := _make_label("DESIGNS", 64, HORIZONTAL_ALIGNMENT_CENTER)
    _place(title, Vector2(100, 165), Vector2(880, 90), themes_layer)

    var subtitle := _make_muted_label("Preview every design. Premium designs unlock through the store.", 21, HORIZONTAL_ALIGNMENT_CENTER)
    _place(subtitle, Vector2(130, 255), Vector2(820, 70), themes_layer)
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var y_positions := [360.0, 560.0, 760.0, 960.0]
    for i in range(THEME_IDS.size()):
        _build_theme_card(THEME_IDS[i], Vector2(130, y_positions[i]))

    var preview_panel := _make_panel("card")
    _place(preview_panel, Vector2(130, 1190), Vector2(820, 245), themes_layer)
    theme_preview_title = _make_label("MIDNIGHT", 34, HORIZONTAL_ALIGNMENT_CENTER)
    _place(theme_preview_title, Vector2(35, 30), Vector2(750, 52), preview_panel)
    theme_preview_detail = _make_muted_label("FREE · EQUIPPED", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(theme_preview_detail, Vector2(35, 86), Vector2(750, 42), preview_panel)
    theme_action_button = _make_button("EQUIPPED", Vector2(660, 82), 26, "accent")
    _place(theme_action_button, Vector2(80, 145), Vector2(660, 82), preview_panel)
    theme_action_button.pressed.connect(_activate_preview_theme)

    theme_status_label = _make_muted_label("Premium purchase wiring follows after visual approval.", 20, HORIZONTAL_ALIGNMENT_CENTER)
    _place(theme_status_label, Vector2(130, 1470), Vector2(820, 80), themes_layer)
    theme_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_theme_card(theme_id: String, pos: Vector2) -> void:
    var panel := _make_panel("soft")
    _place(panel, pos, Vector2(820, 165), themes_layer)

    var swatch := Panel.new()
    var colors := _theme_colors(theme_id)
    swatch.add_theme_stylebox_override("panel", _rounded_box(colors["accent"], 20))
    _place(swatch, Vector2(28, 28), Vector2(110, 109), panel)

    var name := _make_label(_theme_name(theme_id), 29, HORIZONTAL_ALIGNMENT_LEFT)
    _place(name, Vector2(165, 24), Vector2(370, 52), panel)

    var detail_text := "FREE · OWNED" if _is_theme_owned(theme_id) else "PREMIUM · STORE ITEM"
    var detail := _make_muted_label(detail_text, 19, HORIZONTAL_ALIGNMENT_LEFT)
    _place(detail, Vector2(165, 76), Vector2(370, 42), panel)

    var preview := _make_button("PREVIEW", Vector2(220, 76), 22, "secondary")
    _place(preview, Vector2(565, 45), Vector2(220, 76), panel)
    preview.pressed.connect(_preview_theme.bind(theme_id))
    theme_card_buttons[theme_id] = preview

func _make_label(text_value: String, font_size: int, alignment: HorizontalAlignment) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.horizontal_alignment = alignment
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
    return label

func _make_muted_label(text_value: String, font_size: int, alignment: HorizontalAlignment) -> Label:
    var label := _make_label(text_value, font_size, alignment)
    muted_labels.append(label)
    return label

func _make_button(text_value: String, minimum: Vector2, font_size: int = 30, role: String = "secondary") -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = minimum
    button.add_theme_font_size_override("font_size", font_size)
    button.focus_mode = Control.FOCUS_ALL
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.set_meta("theme_role", role)
    themed_buttons.append(button)
    return button

func _make_panel(role: String = "card") -> Panel:
    var panel := Panel.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.set_meta("theme_role", role)
    themed_panels.append(panel)
    return panel

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
    themes_layer.visible = target == AppScreen.THEMES
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
    _refresh_stats_screen()
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
    var colors := _theme_colors(active_theme_id)
    hit_tab_button.modulate = Color.WHITE if leaderboard_mode == "hit" else colors["muted"]
    streak_tab_button.modulate = Color.WHITE if leaderboard_mode == "streak" else colors["muted"]

func _on_leaderboard_loaded(mode: String, top: Array, me: Variant) -> void:
    if screen != AppScreen.LEADERBOARD or mode != leaderboard_mode:
        return
    _clear_leaderboard_rows()
    leaderboard_status_label.text = "BEST HIT · GLOBAL" if mode == "hit" else "LONGEST STREAK · GLOBAL"
    if top.is_empty():
        var empty := _make_muted_label("NO SCORES YET — BE THE FIRST.", 27, HORIZONTAL_ALIGNMENT_CENTER)
        empty.custom_minimum_size = Vector2(820, 100)
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
    var row_panel := _make_panel("row")
    row_panel.custom_minimum_size = Vector2(820, 76)

    var line := HBoxContainer.new()
    line.position = Vector2(18, 4)
    line.size = Vector2(784, 68)
    line.add_theme_constant_override("separation", 10)
    row_panel.add_child(line)

    var rank_label := _make_label("#%d" % int(row.get("rank", 0)), 25, HORIZONTAL_ALIGNMENT_LEFT)
    rank_label.custom_minimum_size = Vector2(95, 68)
    line.add_child(rank_label)

    var name_label := _make_label(str(row.get("display_name", "PLAYER")), 25, HORIZONTAL_ALIGNMENT_LEFT)
    name_label.custom_minimum_size = Vector2(350, 68)
    if str(row.get("player_id", "")) == player_id:
        name_label.add_theme_color_override("font_color", _theme_colors(active_theme_id)["success"])
    line.add_child(name_label)

    var hit := float(int(row.get("best_hit_milli", 0))) / 1000.0
    var server_streak := int(row.get("best_streak", 0))
    var value_text := "%.3f%% · S%d" % [hit, server_streak] if mode == "hit" else "S%d · %.3f%%" % [server_streak, hit]
    var value_label := _make_label(value_text, 24, HORIZONTAL_ALIGNMENT_RIGHT)
    value_label.custom_minimum_size = Vector2(320, 68)
    line.add_child(value_label)

    leaderboard_rows.add_child(row_panel)

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
    pass

func _open_settings() -> void:
    name_input.text = player_name
    name_input.release_focus()
    settings_status_label.text = "2–18 characters · A–Z · 0–9 · space · _ · -"
    _style_name_input(false)
    _show_screen(AppScreen.SETTINGS)

func _close_settings() -> void:
    name_input.release_focus()
    _show_screen(AppScreen.MENU)

func _on_name_input_gui_input(event: InputEvent) -> void:
    var pressed := false
    if event is InputEventScreenTouch:
        pressed = event.pressed
    elif event is InputEventMouseButton:
        pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
    if pressed:
        name_input.grab_focus()

func _on_name_focus_entered() -> void:
    _style_name_input(true)
    settings_status_label.text = "TYPE YOUR PLAYER NAME, THEN TAP SAVE"

func _on_name_focus_exited() -> void:
    _style_name_input(false)

func _style_name_input(focused: bool) -> void:
    if name_input == null:
        return
    var colors := _theme_colors(active_theme_id)
    var base_color: Color = colors["input"]
    var border_color: Color = colors["accent"] if focused else colors["border"]
    name_input.add_theme_stylebox_override("normal", _outlined_box(base_color, border_color, 22, 3 if focused else 2))
    name_input.add_theme_stylebox_override("focus", _outlined_box(base_color, colors["accent"], 22, 4))
    name_input.add_theme_color_override("font_color", colors["text"])
    name_input.add_theme_color_override("caret_color", colors["accent"])
    name_input.add_theme_color_override("selection_color", Color(colors["accent"], 0.34))

func _save_player_name() -> void:
    var requested := name_input.text.strip_edges().to_upper()
    if requested.length() < 2 or requested.length() > 18:
        settings_status_label.text = "NAME MUST BE 2–18 CHARACTERS"
        settings_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
        return
    var regex := RegEx.new()
    regex.compile("^[A-Z0-9 _-]+$")
    if regex.search(requested) == null:
        settings_status_label.text = "USE ONLY A–Z, 0–9, SPACE, _ OR -"
        settings_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
        return
    name_input.release_focus()
    settings_status_label.text = "SAVING..."
    settings_status_label.add_theme_color_override("font_color", _theme_colors(active_theme_id)["muted"])
    leaderboard_service.save_name(player_id, requested)

func _on_name_saved(player: Dictionary) -> void:
    player_name = str(player.get("display_name", name_input.text.strip_edges().to_upper()))
    name_input.text = player_name
    settings_status_label.text = "SAVED · %s" % player_name
    settings_status_label.add_theme_color_override("font_color", _theme_colors(active_theme_id)["success"])
    _refresh_stats_screen()
    _save()

func _on_name_save_failed(message: String) -> void:
    settings_status_label.text = message.to_upper()
    settings_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))

func _open_themes() -> void:
    preview_theme_id = selected_theme_id
    active_theme_id = selected_theme_id
    _apply_theme_to_controls()
    _refresh_theme_screen()
    _show_screen(AppScreen.THEMES)

func _close_themes() -> void:
    active_theme_id = selected_theme_id
    preview_theme_id = selected_theme_id
    _apply_theme_to_controls()
    _show_screen(AppScreen.MENU)

func _preview_theme(theme_id: String) -> void:
    if not THEME_IDS.has(theme_id):
        return
    preview_theme_id = theme_id
    active_theme_id = theme_id
    _apply_theme_to_controls()
    _refresh_theme_screen()
    theme_status_label.text = "PREVIEWING %s" % _theme_name(theme_id)

func _activate_preview_theme() -> void:
    if _is_theme_owned(preview_theme_id):
        selected_theme_id = preview_theme_id
        active_theme_id = selected_theme_id
        _save()
        _apply_theme_to_controls()
        _refresh_theme_screen()
        theme_status_label.text = "%s EQUIPPED" % _theme_name(selected_theme_id)
    else:
        theme_status_label.text = "%s IS PREMIUM · PURCHASE REQUIRED" % _theme_name(preview_theme_id)

func _refresh_theme_screen() -> void:
    if theme_preview_title == null:
        return
    theme_preview_title.text = _theme_name(preview_theme_id)
    var owned := _is_theme_owned(preview_theme_id)
    var equipped := preview_theme_id == selected_theme_id
    if equipped:
        theme_preview_detail.text = ("FREE" if preview_theme_id == "midnight" else "OWNED") + " · EQUIPPED"
        theme_action_button.text = "EQUIPPED"
    elif owned:
        theme_preview_detail.text = "OWNED · READY TO EQUIP"
        theme_action_button.text = "EQUIP DESIGN"
    else:
        theme_preview_detail.text = "PREMIUM · STORE PURCHASE REQUIRED"
        theme_action_button.text = "PREMIUM · LOCKED"

    for theme_id in theme_card_buttons.keys():
        var button: Button = theme_card_buttons[theme_id]
        button.text = "VIEWING" if theme_id == preview_theme_id else "PREVIEW"

func _is_theme_owned(theme_id: String) -> bool:
    return theme_id == "midnight" or owned_themes.has(theme_id)

func _theme_name(theme_id: String) -> String:
    match theme_id:
        "neon": return "NEON PULSE"
        "gold": return "GOLD RUSH"
        "aurora": return "AURORA"
        _: return "MIDNIGHT"

func _theme_colors(theme_id: String) -> Dictionary:
    match theme_id:
        "neon":
            return {
                "bg": Color(0.018, 0.008, 0.035),
                "glow": Color(0.20, 0.02, 0.32, 0.42),
                "glow2": Color(0.00, 0.28, 0.34, 0.28),
                "surface": Color(0.075, 0.045, 0.12),
                "surface2": Color(0.055, 0.035, 0.09),
                "input": Color(0.035, 0.022, 0.055),
                "accent": Color(0.95, 0.18, 0.72),
                "accent2": Color(0.10, 0.88, 0.95),
                "text": Color(0.98, 0.97, 1.0),
                "muted": Color(0.68, 0.61, 0.78),
                "border": Color(0.28, 0.19, 0.38),
                "success": Color(0.18, 1.0, 0.72),
                "premium": Color(1.0, 0.78, 0.22),
            }
        "gold":
            return {
                "bg": Color(0.022, 0.018, 0.010),
                "glow": Color(0.24, 0.16, 0.02, 0.46),
                "glow2": Color(0.12, 0.07, 0.01, 0.30),
                "surface": Color(0.11, 0.085, 0.035),
                "surface2": Color(0.075, 0.055, 0.025),
                "input": Color(0.045, 0.035, 0.018),
                "accent": Color(0.96, 0.70, 0.18),
                "accent2": Color(1.0, 0.88, 0.42),
                "text": Color(1.0, 0.98, 0.91),
                "muted": Color(0.73, 0.66, 0.50),
                "border": Color(0.34, 0.26, 0.10),
                "success": Color(0.42, 0.92, 0.48),
                "premium": Color(1.0, 0.78, 0.22),
            }
        "aurora":
            return {
                "bg": Color(0.008, 0.025, 0.032),
                "glow": Color(0.00, 0.30, 0.30, 0.40),
                "glow2": Color(0.22, 0.08, 0.34, 0.28),
                "surface": Color(0.035, 0.11, 0.12),
                "surface2": Color(0.025, 0.075, 0.09),
                "input": Color(0.018, 0.052, 0.062),
                "accent": Color(0.14, 0.86, 0.72),
                "accent2": Color(0.58, 0.38, 1.0),
                "text": Color(0.94, 1.0, 0.99),
                "muted": Color(0.55, 0.72, 0.72),
                "border": Color(0.12, 0.30, 0.31),
                "success": Color(0.28, 1.0, 0.66),
                "premium": Color(1.0, 0.78, 0.22),
            }
        _:
            return {
                "bg": Color(0.008, 0.014, 0.028),
                "glow": Color(0.045, 0.07, 0.15, 0.48),
                "glow2": Color(0.03, 0.13, 0.23, 0.32),
                "surface": Color(0.065, 0.085, 0.14),
                "surface2": Color(0.045, 0.060, 0.105),
                "input": Color(0.025, 0.033, 0.055),
                "accent": Color(0.16, 0.56, 0.93),
                "accent2": Color(0.20, 0.84, 0.94),
                "text": Color(0.96, 0.98, 1.0),
                "muted": Color(0.52, 0.59, 0.72),
                "border": Color(0.13, 0.17, 0.27),
                "success": Color(0.22, 0.90, 0.62),
                "premium": Color(1.0, 0.78, 0.22),
            }

func _apply_theme_to_controls() -> void:
    var colors := _theme_colors(active_theme_id)
    for button in themed_buttons:
        if not is_instance_valid(button):
            continue
        var role := str(button.get_meta("theme_role", "secondary"))
        var normal: Color
        var hover: Color
        var pressed: Color
        match role:
            "accent":
                normal = colors["accent"]
                hover = Color(colors["accent"]).lightened(0.10)
                pressed = Color(colors["accent"]).darkened(0.14)
            "ghost":
                normal = Color(colors["surface2"], 0.70)
                hover = Color(colors["surface"], 0.90)
                pressed = Color(colors["surface2"], 1.0)
            _:
                normal = colors["surface"]
                hover = Color(colors["surface"]).lightened(0.07)
                pressed = Color(colors["surface"]).darkened(0.10)
        button.add_theme_color_override("font_color", colors["text"])
        button.add_theme_color_override("font_hover_color", Color.WHITE)
        button.add_theme_color_override("font_pressed_color", colors["text"])
        button.add_theme_stylebox_override("normal", _outlined_box(normal, colors["border"], 24, 1))
        button.add_theme_stylebox_override("hover", _outlined_box(hover, colors["accent"], 24, 2))
        button.add_theme_stylebox_override("pressed", _outlined_box(pressed, colors["accent"], 24, 2))
        button.add_theme_stylebox_override("focus", _outlined_box(normal, colors["accent2"], 24, 3))

    for panel in themed_panels:
        if not is_instance_valid(panel):
            continue
        var role := str(panel.get_meta("theme_role", "card"))
        var fill: Color = colors["surface"]
        var border: Color = colors["border"]
        var radius := 28
        if role == "soft":
            fill = Color(colors["surface2"], 0.86)
            radius = 26
        elif role == "row":
            fill = Color(colors["surface2"], 0.82)
            radius = 20
        panel.add_theme_stylebox_override("panel", _outlined_box(fill, border, radius, 1))

    for label in muted_labels:
        if is_instance_valid(label):
            label.add_theme_color_override("font_color", colors["muted"])

    if name_input != null:
        _style_name_input(name_input.has_focus())
    if menu_theme_label != null:
        menu_theme_label.text = "THEME · %s" % _theme_name(selected_theme_id)
    _refresh_leaderboard_tabs()
    queue_redraw()

func _refresh_labels() -> void:
    streak_label.text = "STREAK  %d" % streak
    best_label.text = "BEST  %s" % _format_percent(best_value)

func _refresh_menu_stats() -> void:
    if menu_best_label != null:
        menu_best_label.text = _format_percent(best_value)
    if menu_streak_label != null:
        menu_streak_label.text = str(best_streak)
    if menu_theme_label != null:
        menu_theme_label.text = "THEME · %s" % _theme_name(selected_theme_id)

func _refresh_stats_screen() -> void:
    if stats_best_value_label != null:
        stats_best_value_label.text = _format_percent(best_value)
    if stats_streak_value_label != null:
        stats_streak_value_label.text = str(best_streak)
    if stats_rounds_value_label != null:
        stats_rounds_value_label.text = str(games_played)
    if stats_perfect_value_label != null:
        stats_perfect_value_label.text = str(local_perfect_count)
    if stats_player_label != null:
        stats_player_label.text = player_name

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
    var colors := _theme_colors(active_theme_id)
    draw_rect(Rect2(Vector2.ZERO, size), colors["bg"], true)

    if screen != AppScreen.GAME:
        draw_circle(Vector2(540, 610), 520.0, colors["glow"])
        draw_circle(Vector2(540, 690), 315.0, colors["glow2"])
        draw_circle(Vector2(870, 245), 135.0, Color(colors["accent"], 0.08))
        return

    var shake := Vector2.ZERO
    if shake_time > 0.0 and not game_paused:
        shake = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 5.0))

    draw_circle(Vector2(540, 710) + shake, 540.0, colors["glow"])
    draw_circle(Vector2(540, 720) + shake, 340.0, colors["glow2"])

    var meter_rect := Rect2(Vector2(115, 805) + shake, Vector2(850, 110))
    draw_style_box(_rounded_box(colors["surface"], 28), meter_rect)

    var inner := Rect2(meter_rect.position + Vector2(13, 13), Vector2(meter_rect.size.x - 26, meter_rect.size.y - 26))
    draw_style_box(_rounded_box(colors["input"], 20), inner)

    var zone_width := maxf(8.0, inner.size.x * ((100.0 - STREAK_THRESHOLD) / 100.0) * 18.0)
    var zone := Rect2(Vector2(inner.end.x - zone_width, inner.position.y), Vector2(zone_width, inner.size.y))
    draw_rect(zone, Color(colors["success"], 0.24), true)

    var fill_width := inner.size.x * (meter_value / TARGET)
    if state == GameState.RESULT:
        fill_width = inner.size.x * (result_value / TARGET)
    if fill_width > 0.0:
        var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
        draw_style_box(_rounded_box(_meter_color(state == GameState.RESULT), 20), fill_rect)

    draw_line(Vector2(inner.end.x, inner.position.y - 26), Vector2(inner.end.x, inner.end.y + 26), colors["premium"], 5.0)
    var cursor_value := result_value if state == GameState.RESULT else meter_value
    var cursor_x := inner.position.x + inner.size.x * (cursor_value / TARGET)
    draw_line(Vector2(cursor_x, inner.position.y - 16), Vector2(cursor_x, inner.end.y + 16), colors["text"], 7.0)

    for tick in range(0, 101, 10):
        var x := inner.position.x + inner.size.x * (float(tick) / 100.0)
        draw_line(Vector2(x, inner.end.y + 8), Vector2(x, inner.end.y + (24 if tick % 50 == 0 else 17)), Color(colors["muted"], 0.50), 2.0)

    for particle in particles:
        var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
        draw_circle(Vector2(particle["p"]), float(particle["size"]), Color(colors["accent2"], life_ratio))

    if flash_alpha > 0.0 and not game_paused:
        draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, flash_alpha * 0.12), true)

func _meter_color(is_result: bool) -> Color:
    var colors := _theme_colors(active_theme_id)
    var value := result_value if is_result else meter_value
    if value >= STREAK_THRESHOLD:
        return colors["success"]
    if value >= 95.0:
        return colors["premium"]
    return colors["accent"]

func _rounded_box(color: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    return style

func _outlined_box(color: Color, border_color: Color, radius: int, border_width: int) -> StyleBoxFlat:
    var style := _rounded_box(color, radius)
    style.border_color = border_color
    style.border_width_left = border_width
    style.border_width_top = border_width
    style.border_width_right = border_width
    style.border_width_bottom = border_width
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
    selected_theme_id = str(parsed.get("selected_theme", "midnight"))
    if not THEME_IDS.has(selected_theme_id):
        selected_theme_id = "midnight"

    owned_themes.clear()
    owned_themes.append("midnight")
    var saved_owned = parsed.get("owned_themes", [])
    if typeof(saved_owned) == TYPE_ARRAY:
        for item in saved_owned:
            var theme_id := str(item)
            if THEME_IDS.has(theme_id) and not owned_themes.has(theme_id):
                owned_themes.append(theme_id)

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
        "selected_theme": selected_theme_id,
        "owned_themes": owned_themes,
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
