extends Control

const SAVE_PATH := "user://save.json"
const TARGET := 100.0
const STREAK_THRESHOLD := 99.900
const PERFECT_WINDOW := 0.005
const MAX_PARTICLES := 30

enum GameState { READY, RUNNING, RESULT }

var state: GameState = GameState.READY
var meter_value: float = 0.0
var meter_phase: float = 0.0
var meter_speed: float = 2.45 # radians/second; half-cycle reaches 100%
var round_number: int = 1
var streak: int = 0
var best_streak: int = 0
var best_value: float = 0.0
var games_played: int = 0
var result_value: float = 0.0
var result_title: String = ""
var result_subtitle: String = ""
var pulse_time: float = 0.0
var shake_time: float = 0.0
var flash_alpha: float = 0.0
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var title_label: Label
var percent_label: Label
var hint_label: Label
var best_label: Label
var streak_label: Label
var result_label: Label
var result_detail_label: Label
var footer_label: Label

func _ready() -> void:
    rng.randomize()
    _load_save()
    _build_ui()
    set_process(true)
    queue_redraw()

func _build_ui() -> void:
    title_label = _make_label("99.9%", 86, HORIZONTAL_ALIGNMENT_CENTER)
    title_label.position = Vector2(90, 135)
    title_label.size = Vector2(900, 120)
    title_label.modulate = Color(0.95, 0.97, 1.0)
    add_child(title_label)

    var tagline := _make_label("HOW CLOSE CAN YOU GET?", 27, HORIZONTAL_ALIGNMENT_CENTER)
    tagline.position = Vector2(90, 258)
    tagline.size = Vector2(900, 52)
    tagline.modulate = Color(0.52, 0.57, 0.68)
    add_child(tagline)

    percent_label = _make_label("0.000%", 112, HORIZONTAL_ALIGNMENT_CENTER)
    percent_label.position = Vector2(90, 590)
    percent_label.size = Vector2(900, 150)
    percent_label.modulate = Color(0.97, 0.98, 1.0)
    add_child(percent_label)

    streak_label = _make_label("STREAK  0", 30, HORIZONTAL_ALIGNMENT_LEFT)
    streak_label.position = Vector2(115, 350)
    streak_label.size = Vector2(400, 55)
    streak_label.modulate = Color(0.62, 0.67, 0.78)
    add_child(streak_label)

    best_label = _make_label("BEST  0.000%", 30, HORIZONTAL_ALIGNMENT_RIGHT)
    best_label.position = Vector2(565, 350)
    best_label.size = Vector2(400, 55)
    best_label.modulate = Color(0.62, 0.67, 0.78)
    add_child(best_label)

    result_label = _make_label("", 62, HORIZONTAL_ALIGNMENT_CENTER)
    result_label.position = Vector2(90, 1010)
    result_label.size = Vector2(900, 90)
    add_child(result_label)

    result_detail_label = _make_label("", 30, HORIZONTAL_ALIGNMENT_CENTER)
    result_detail_label.position = Vector2(100, 1100)
    result_detail_label.size = Vector2(880, 130)
    result_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    result_detail_label.modulate = Color(0.66, 0.71, 0.80)
    add_child(result_detail_label)

    hint_label = _make_label("TAP TO START", 40, HORIZONTAL_ALIGNMENT_CENTER)
    hint_label.position = Vector2(120, 1370)
    hint_label.size = Vector2(840, 80)
    hint_label.modulate = Color(0.88, 0.91, 1.0)
    add_child(hint_label)

    footer_label = _make_label("Hit 99.900%+ to keep your streak", 25, HORIZONTAL_ALIGNMENT_CENTER)
    footer_label.position = Vector2(90, 1690)
    footer_label.size = Vector2(900, 60)
    footer_label.modulate = Color(0.38, 0.42, 0.52)
    add_child(footer_label)

    _refresh_labels()

func _make_label(text_value: String, font_size: int, alignment: HorizontalAlignment) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.horizontal_alignment = alignment
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label

func _process(delta: float) -> void:
    pulse_time += delta
    flash_alpha = maxf(0.0, flash_alpha - delta * 2.7)
    shake_time = maxf(0.0, shake_time - delta)

    if state == GameState.RUNNING:
        meter_phase = fmod(meter_phase + meter_speed * delta, TAU)
        # Cosine motion gives a tiny natural slowdown near 100%. This keeps
        # 99.9x values skill-based and reachable instead of frame-rate lottery.
        meter_value = 50.0 - 50.0 * cos(meter_phase)
        percent_label.text = _format_percent(meter_value)

    _update_particles(delta)
    hint_label.modulate.a = 0.72 + sin(pulse_time * 4.0) * 0.18
    queue_redraw()

func _input(event: InputEvent) -> void:
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

    _evaluate_result(result_value)
    _spawn_result_particles(result_value)
    _save()
    _refresh_labels()
    hint_label.text = "TAP FOR NEXT ROUND"
    percent_label.text = _format_percent(result_value)

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

func _refresh_labels() -> void:
    streak_label.text = "STREAK  %d" % streak
    best_label.text = "BEST  %s" % _format_percent(best_value)

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
    var shake := Vector2.ZERO
    if shake_time > 0.0:
        shake = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 5.0))

    # Background glow.
    draw_circle(Vector2(540, 710) + shake, 540.0, Color(0.055, 0.070, 0.12, 0.45))
    draw_circle(Vector2(540, 720) + shake, 340.0, Color(0.07, 0.11, 0.19, 0.40))

    # Meter shell.
    var meter_rect := Rect2(Vector2(115, 805) + shake, Vector2(850, 110))
    draw_style_box(_rounded_box(Color(0.075, 0.085, 0.12, 1.0), 28), meter_rect)

    var inner := Rect2(meter_rect.position + Vector2(13, 13), Vector2(meter_rect.size.x - 26, meter_rect.size.y - 26))
    draw_style_box(_rounded_box(Color(0.025, 0.030, 0.048, 1.0), 20), inner)

    # 99.9% danger zone.
    var zone_width := maxf(8.0, inner.size.x * ((100.0 - STREAK_THRESHOLD) / 100.0) * 18.0)
    var zone := Rect2(Vector2(inner.end.x - zone_width, inner.position.y), Vector2(zone_width, inner.size.y))
    draw_rect(zone, Color(0.22, 0.86, 0.62, 0.28), true)

    # Progress fill.
    var fill_width := inner.size.x * (meter_value / TARGET)
    if state == GameState.RESULT:
        fill_width = inner.size.x * (result_value / TARGET)
    if fill_width > 0.0:
        var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
        var fill_color := _meter_color(state == GameState.RESULT)
        draw_style_box(_rounded_box(fill_color, 20), fill_rect)

    # Target line and cursor.
    draw_line(Vector2(inner.end.x, inner.position.y - 26), Vector2(inner.end.x, inner.end.y + 26), Color(1.0, 0.85, 0.35), 5.0)
    var cursor_x := inner.position.x + inner.size.x * ((result_value if state == GameState.RESULT else meter_value) / TARGET)
    draw_line(Vector2(cursor_x, inner.position.y - 16), Vector2(cursor_x, inner.end.y + 16), Color(1.0, 1.0, 1.0), 7.0)

    # Tick marks.
    for tick in range(0, 101, 10):
        var x := inner.position.x + inner.size.x * (float(tick) / 100.0)
        draw_line(Vector2(x, inner.end.y + 8), Vector2(x, inner.end.y + (24 if tick % 50 == 0 else 17)), Color(0.35, 0.39, 0.48, 0.55), 2.0)

    # Result particles.
    for particle in particles:
        var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
        draw_circle(Vector2(particle["p"]), float(particle["size"]), Color(0.65, 0.92, 1.0, life_ratio))

    if flash_alpha > 0.0:
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

func _save() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        return
    var payload := {
        "best_value": best_value,
        "best_streak": best_streak,
        "games_played": games_played,
    }
    file.store_string(JSON.stringify(payload))
