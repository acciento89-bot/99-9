extends "res://scripts/main_v3.gd"

# Build 4 hardens gameplay touch routing and adds an animated themed atmosphere.
# The gameplay surface owns game taps directly; UI buttons keep their own input.

func _ready() -> void:
    super._ready()
    gameplay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
    gameplay_layer.gui_input.connect(_on_gameplay_surface_input)
    queue_redraw()

func _unhandled_input(_event: InputEvent) -> void:
    # Intentionally disabled in Build 4. Full-screen Controls can consume touch input
    # before it reaches _unhandled_input on mobile. Gameplay now uses gui_input.
    pass

func _on_gameplay_surface_input(event: InputEvent) -> void:
    if screen != AppScreen.GAME or game_paused:
        return

    var tapped := false
    var tap_position := Vector2.ZERO
    if event is InputEventScreenTouch:
        tapped = event.pressed
        tap_position = event.position
    elif event is InputEventMouseButton:
        tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
        tap_position = event.position

    if not tapped:
        return

    # Safety guard around the pause control. The Button normally consumes this
    # itself, but the guard prevents a pause tap ever counting as a game tap.
    if Rect2(Vector2(895, 30), Vector2(165, 125)).has_point(tap_position):
        return

    accept_event()
    match state:
        GameState.READY:
            _start_round()
        GameState.RUNNING:
            _stop_round()
        GameState.RESULT:
            _next_round()

func _draw() -> void:
    var colors := _theme_colors(active_theme_id)
    draw_rect(Rect2(Vector2.ZERO, size), colors["bg"], true)
    _draw_atmosphere(colors, screen == AppScreen.GAME)

    if screen != AppScreen.GAME:
        _draw_menu_atmosphere(colors)
        return

    _draw_game_surface(colors)

func _draw_atmosphere(colors: Dictionary, subdued: bool) -> void:
    var strength := 0.58 if subdued else 1.0

    # Soft vertical color wash instead of a flat black canvas.
    for i in range(16):
        var t := float(i) / 15.0
        var band_y := t * size.y
        var band_h := size.y / 15.0 + 2.0
        var alpha: float = (0.022 + (1.0 - absf(t - 0.38) * 1.45) * 0.026) * strength
        draw_rect(Rect2(0.0, band_y, size.x, band_h), Color(colors["accent"], maxf(alpha, 0.008)), true)

    # Slowly moving glow clouds.
    var p1 := Vector2(180.0 + sin(pulse_time * 0.23) * 90.0, 430.0 + cos(pulse_time * 0.19) * 70.0)
    var p2 := Vector2(900.0 + cos(pulse_time * 0.17) * 120.0, 980.0 + sin(pulse_time * 0.21) * 105.0)
    var p3 := Vector2(520.0 + sin(pulse_time * 0.13) * 160.0, 1540.0 + cos(pulse_time * 0.16) * 80.0)
    _draw_soft_orb(p1, 360.0, colors["accent"], 0.10 * strength)
    _draw_soft_orb(p2, 430.0, colors["accent2"], 0.075 * strength)
    _draw_soft_orb(p3, 390.0, colors["glow"], 0.11 * strength)

    # Fine star/dust field, deterministic so it never jitters frame-to-frame.
    for i in range(30):
        var x := fmod(float(i * 173 + 61), 1080.0)
        var y := fmod(float(i * 293 + 137), 1920.0)
        var twinkle := 0.055 + 0.055 * (0.5 + 0.5 * sin(pulse_time * (1.0 + float(i % 5) * 0.08) + float(i)))
        var radius := 1.2 + float(i % 3) * 0.65
        draw_circle(Vector2(x, y), radius, Color(colors["accent2"], twinkle * strength))

    # Theme-dependent texture so every design has a distinct backdrop character.
    match active_theme_id:
        "neon":
            _draw_neon_grid(colors, strength)
        "gold":
            _draw_gold_rays(colors, strength)
        "aurora":
            _draw_aurora_ribbons(colors, strength)
        _:
            _draw_midnight_rings(colors, strength)

func _draw_menu_atmosphere(colors: Dictionary) -> void:
    draw_circle(Vector2(540, 600), 505.0, Color(colors["glow"], 0.34))
    draw_circle(Vector2(540, 650), 325.0, Color(colors["glow2"], 0.28))
    draw_arc(Vector2(540, 610), 455.0, -2.8, 0.25, 80, Color(colors["accent"], 0.11), 2.0, true)
    draw_arc(Vector2(540, 610), 390.0, 0.45, 3.35, 80, Color(colors["accent2"], 0.075), 2.0, true)

func _draw_game_surface(colors: Dictionary) -> void:
    var shake := Vector2.ZERO
    if shake_time > 0.0 and not game_paused:
        shake = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 5.0))

    draw_circle(Vector2(540, 710) + shake, 505.0, Color(colors["glow"], 0.31))
    draw_circle(Vector2(540, 720) + shake, 325.0, Color(colors["glow2"], 0.30))
    draw_arc(Vector2(540, 710) + shake, 430.0, -2.75, 0.1, 72, Color(colors["accent"], 0.09), 2.0, true)

    var meter_rect := Rect2(Vector2(115, 805) + shake, Vector2(850, 110))
    draw_style_box(_outlined_box(colors["surface"], Color(colors["border"], 0.9), 28, 2), meter_rect)

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

func _draw_soft_orb(center: Vector2, radius: float, color: Color, max_alpha: float) -> void:
    for layer in range(8, 0, -1):
        var t := float(layer) / 8.0
        draw_circle(center, radius * t, Color(color, max_alpha * (1.0 - t) * 0.44 + max_alpha * 0.035))

func _draw_midnight_rings(colors: Dictionary, strength: float) -> void:
    var center := Vector2(540.0, 680.0)
    for i in range(4):
        var radius := 280.0 + float(i) * 115.0 + sin(pulse_time * 0.18 + float(i)) * 8.0
        draw_arc(center, radius, -2.85 + float(i) * 0.24, -0.15 + float(i) * 0.17, 56, Color(colors["accent2"], 0.045 * strength), 1.5, true)

func _draw_neon_grid(colors: Dictionary, strength: float) -> void:
    var drift := fmod(pulse_time * 10.0, 120.0)
    for x in range(-120, 1201, 120):
        draw_line(Vector2(float(x) + drift, 0), Vector2(float(x) - 190.0 + drift, 1920), Color(colors["accent2"], 0.032 * strength), 1.0)
    for y in range(260, 1921, 120):
        draw_line(Vector2(0, float(y)), Vector2(1080, float(y)), Color(colors["accent"], 0.025 * strength), 1.0)

func _draw_gold_rays(colors: Dictionary, strength: float) -> void:
    var origin := Vector2(540, 150)
    for i in range(9):
        var angle := -1.15 + float(i) * 0.285 + sin(pulse_time * 0.12) * 0.025
        var endpoint := origin + Vector2(cos(angle), sin(angle)) * 2050.0
        draw_line(origin, endpoint, Color(colors["accent2"], 0.024 * strength), 3.0)

func _draw_aurora_ribbons(colors: Dictionary, strength: float) -> void:
    for ribbon in range(4):
        var points := PackedVector2Array()
        for step in range(25):
            var x := -80.0 + float(step) * 52.0
            var y := 270.0 + float(ribbon) * 300.0 + sin(float(step) * 0.47 + pulse_time * (0.20 + float(ribbon) * 0.035)) * (55.0 + float(ribbon) * 9.0)
            points.append(Vector2(x, y))
        var ribbon_color: Color = colors["accent"] if ribbon % 2 == 0 else colors["accent2"]
        draw_polyline(points, Color(ribbon_color, 0.055 * strength), 18.0, true)
        draw_polyline(points, Color(ribbon_color, 0.08 * strength), 2.0, true)
