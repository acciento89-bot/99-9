extends "res://scripts/main_v5.gd"

# Build 6 visual-overhaul branch.
# Premium themes use recognizable scene language instead of generic glow circles.
# Build 5 remains the current TestFlight validation target; this branch is not uploaded yet.

func _draw_atmosphere(colors: Dictionary, subdued: bool) -> void:
    var strength: float = 0.56 if subdued else 1.0
    _draw_depth_wash(colors, strength)

    match active_theme_id:
        "neon":
            _draw_neon_city(colors, strength)
        "gold":
            _draw_obsidian_gold(colors, strength)
        "aurora":
            _draw_polar_aurora(colors, strength)
        _:
            _draw_midnight_constellations(colors, strength)

    _draw_edge_falloff(colors, strength)

func _draw_menu_atmosphere(colors: Dictionary) -> void:
    # Architectural framing instead of the old giant concentric circles.
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    var surface: Color = colors["surface"]

    var hero := PackedVector2Array([
        Vector2(120, 315),
        Vector2(960, 315),
        Vector2(1020, 1040),
        Vector2(60, 1040),
    ])
    draw_colored_polygon(hero, Color(surface, 0.10))
    draw_line(Vector2(120, 315), Vector2(960, 315), Color(accent, 0.16), 2.0, true)
    draw_line(Vector2(60, 1040), Vector2(1020, 1040), Color(accent2, 0.10), 2.0, true)

    for i in range(5):
        var inset: float = 70.0 + float(i) * 38.0
        var alpha: float = 0.055 - float(i) * 0.007
        draw_line(Vector2(inset, 260), Vector2(0, 330 + float(i) * 86.0), Color(accent, alpha), 1.5, true)
        draw_line(Vector2(1080 - inset, 260), Vector2(1080, 330 + float(i) * 86.0), Color(accent2, alpha), 1.5, true)

func _draw_game_surface(colors: Dictionary) -> void:
    var shake := Vector2.ZERO
    if shake_time > 0.0 and not game_paused:
        shake = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 5.0))

    # Focus stage around the precision meter. No giant circles behind gameplay.
    var stage := PackedVector2Array([
        Vector2(150, 735) + shake,
        Vector2(930, 735) + shake,
        Vector2(995, 995) + shake,
        Vector2(85, 995) + shake,
    ])
    draw_colored_polygon(stage, Color(colors["surface"], 0.13))
    draw_line(Vector2(150, 735) + shake, Vector2(930, 735) + shake, Color(colors["accent"], 0.18), 2.0, true)
    draw_line(Vector2(105, 975) + shake, Vector2(975, 975) + shake, Color(colors["accent2"], 0.10), 2.0, true)
    draw_line(Vector2(150, 735) + shake, Vector2(85, 995) + shake, Color(colors["border"], 0.22), 1.0, true)
    draw_line(Vector2(930, 735) + shake, Vector2(995, 995) + shake, Color(colors["border"], 0.22), 1.0, true)

    var meter_rect := Rect2(Vector2(115, 805) + shake, Vector2(850, 110))
    draw_style_box(_outlined_box(colors["surface"], Color(colors["border"], 0.9), 28, 2), meter_rect)

    var inner := Rect2(meter_rect.position + Vector2(13, 13), Vector2(meter_rect.size.x - 26, meter_rect.size.y - 26))
    draw_style_box(_rounded_box(colors["input"], 20), inner)

    var zone_width: float = maxf(8.0, inner.size.x * ((100.0 - STREAK_THRESHOLD) / 100.0) * 18.0)
    var zone := Rect2(Vector2(inner.end.x - zone_width, inner.position.y), Vector2(zone_width, inner.size.y))
    draw_rect(zone, Color(colors["success"], 0.24), true)

    var fill_width: float = inner.size.x * (meter_value / TARGET)
    if state == GameState.RESULT:
        fill_width = inner.size.x * (result_value / TARGET)
    if fill_width > 0.0:
        var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
        draw_style_box(_rounded_box(_meter_color(state == GameState.RESULT), 20), fill_rect)

    draw_line(Vector2(inner.end.x, inner.position.y - 26), Vector2(inner.end.x, inner.end.y + 26), colors["premium"], 5.0)
    var cursor_value: float = result_value if state == GameState.RESULT else meter_value
    var cursor_x: float = inner.position.x + inner.size.x * (cursor_value / TARGET)
    draw_line(Vector2(cursor_x, inner.position.y - 16), Vector2(cursor_x, inner.end.y + 16), colors["text"], 7.0)

    for tick in range(0, 101, 10):
        var x: float = inner.position.x + inner.size.x * (float(tick) / 100.0)
        draw_line(Vector2(x, inner.end.y + 8), Vector2(x, inner.end.y + (24 if tick % 50 == 0 else 17)), Color(colors["muted"], 0.50), 2.0)

    for particle in particles:
        var life_ratio: float = clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
        _draw_diamond(Vector2(particle["p"]), float(particle["size"]) * 1.15, Color(colors["accent2"], life_ratio))

    if flash_alpha > 0.0 and not game_paused:
        draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, flash_alpha * 0.12), true)

func _draw_depth_wash(colors: Dictionary, strength: float) -> void:
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    for i in range(24):
        var t: float = float(i) / 23.0
        var y: float = t * size.y
        var h: float = size.y / 23.0 + 2.0
        var center_weight: float = maxf(0.0, 1.0 - absf(t - 0.40) * 1.55)
        var c: Color = accent if i % 2 == 0 else accent2
        var alpha: float = (0.008 + center_weight * 0.020) * strength
        draw_rect(Rect2(0.0, y, size.x, h), Color(c, alpha), true)

func _draw_edge_falloff(colors: Dictionary, strength: float) -> void:
    var bg: Color = colors["bg"]
    for i in range(8):
        var t: float = float(i + 1) / 8.0
        var w: float = 20.0 + t * 160.0
        var alpha: float = 0.015 + t * 0.030 * strength
        draw_rect(Rect2(0, 0, w, size.y), Color(bg, alpha), true)
        draw_rect(Rect2(size.x - w, 0, w, size.y), Color(bg, alpha), true)

func _draw_midnight_constellations(colors: Dictionary, strength: float) -> void:
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    var text_color: Color = colors["text"]

    # Diagonal nebula lanes create depth without circular glow blobs.
    for lane in range(6):
        var drift: float = sin(pulse_time * 0.10 + float(lane)) * 18.0
        var y0: float = 170.0 + float(lane) * 250.0 + drift
        var lane_poly := PackedVector2Array([
            Vector2(-140, y0),
            Vector2(1220, y0 + 410),
            Vector2(1220, y0 + 500),
            Vector2(-140, y0 + 90),
        ])
        var lane_color: Color = accent if lane % 2 == 0 else accent2
        draw_colored_polygon(lane_poly, Color(lane_color, (0.014 + float(lane % 3) * 0.006) * strength))

    # Deterministic diamond stars.
    for i in range(56):
        var x: float = fmod(float(i * 197 + 71), 1080.0)
        var y: float = fmod(float(i * 311 + 109), 1920.0)
        var twinkle: float = 0.10 + 0.12 * (0.5 + 0.5 * sin(pulse_time * (0.65 + float(i % 5) * 0.07) + float(i) * 0.83))
        var star_size: float = 1.7 + float(i % 4) * 0.65
        _draw_diamond(Vector2(x, y), star_size, Color(text_color, twinkle * strength))

    var drift_vec := Vector2(sin(pulse_time * 0.08) * 5.0, cos(pulse_time * 0.07) * 4.0)
    var constellation_a := PackedVector2Array([
        Vector2(165, 410) + drift_vec,
        Vector2(292, 355) + drift_vec,
        Vector2(410, 455) + drift_vec,
        Vector2(545, 395) + drift_vec,
        Vector2(665, 480) + drift_vec,
    ])
    var constellation_b := PackedVector2Array([
        Vector2(720, 1125) - drift_vec,
        Vector2(825, 1035) - drift_vec,
        Vector2(920, 1110) - drift_vec,
        Vector2(865, 1260) - drift_vec,
        Vector2(740, 1315) - drift_vec,
    ])
    _draw_constellation(constellation_a, accent2, strength)
    _draw_constellation(constellation_b, accent, strength)

func _draw_constellation(points: PackedVector2Array, color: Color, strength: float) -> void:
    if points.size() < 2:
        return
    draw_polyline(points, Color(color, 0.15 * strength), 1.5, true)
    for p in points:
        _draw_diamond(p, 4.0, Color(color, 0.58 * strength))
        _draw_diamond(p, 1.8, Color(1.0, 1.0, 1.0, 0.82 * strength))

func _draw_neon_city(colors: Dictionary, strength: float) -> void:
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    var surface: Color = colors["surface"]
    var input_color: Color = colors["input"]
    var horizon_y: float = 610.0 if screen == AppScreen.GAME else 650.0
    var vanishing := Vector2(540.0 + sin(pulse_time * 0.07) * 10.0, horizon_y)

    # Distant cyber skyline.
    for i in range(22):
        var building_w: float = 42.0 + float((i * 17) % 38)
        var building_h: float = 55.0 + float((i * 47) % 185)
        var x: float = -10.0 + float(i) * 52.0
        var rect := Rect2(x, horizon_y - building_h, building_w, building_h)
        draw_rect(rect, Color(surface, 0.42 * strength), true)
        if i % 3 == 0:
            draw_rect(Rect2(x + 8.0, horizon_y - building_h + 18.0, 4.0, maxf(8.0, building_h - 36.0)), Color(accent2, 0.14 * strength), true)
        if i % 4 == 1:
            draw_line(Vector2(x + building_w - 7.0, horizon_y - building_h + 12.0), Vector2(x + building_w - 7.0, horizon_y - 12.0), Color(accent, 0.12 * strength), 2.0)

    draw_line(Vector2(0, horizon_y), Vector2(1080, horizon_y), Color(accent, 0.40 * strength), 3.0, true)
    draw_line(Vector2(0, horizon_y + 8), Vector2(1080, horizon_y + 8), Color(accent2, 0.13 * strength), 1.0, true)

    # Perspective lanes converge into a real synthwave horizon.
    for i in range(15):
        var bottom_x: float = -240.0 + float(i) * 112.0
        draw_line(vanishing, Vector2(bottom_x, 1920.0), Color(accent2, 0.085 * strength), 1.5, true)

    for row in range(15):
        var t: float = float(row + 1) / 15.0
        var eased: float = t * t
        var y: float = horizon_y + eased * (1920.0 - horizon_y)
        var alpha: float = (0.035 + t * 0.065) * strength
        draw_line(Vector2(0, y), Vector2(1080, y), Color(accent, alpha), 1.2, true)

    # Slow scan slices add motion without turning into floating circles.
    var scan: float = fmod(pulse_time * 72.0, 520.0)
    for k in range(3):
        var sy: float = horizon_y + 120.0 + fmod(scan + float(k) * 180.0, 580.0)
        draw_rect(Rect2(90, sy, 900, 3), Color(accent2, 0.12 * strength), true)
        draw_rect(Rect2(270, sy + 7, 540, 1), Color(input_color, 0.18 * strength), true)

func _draw_obsidian_gold(colors: Dictionary, strength: float) -> void:
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    var surface: Color = colors["surface"]
    var input_color: Color = colors["input"]

    # Large obsidian facets: architectural, dark and angular.
    var facets: Array[PackedVector2Array] = [
        PackedVector2Array([Vector2(0, 120), Vector2(500, 0), Vector2(390, 620), Vector2(0, 760)]),
        PackedVector2Array([Vector2(500, 0), Vector2(1080, 170), Vector2(720, 690), Vector2(390, 620)]),
        PackedVector2Array([Vector2(0, 760), Vector2(390, 620), Vector2(520, 1290), Vector2(0, 1510)]),
        PackedVector2Array([Vector2(390, 620), Vector2(720, 690), Vector2(650, 1350), Vector2(520, 1290)]),
        PackedVector2Array([Vector2(720, 690), Vector2(1080, 470), Vector2(1080, 1430), Vector2(650, 1350)]),
        PackedVector2Array([Vector2(0, 1510), Vector2(520, 1290), Vector2(1080, 1680), Vector2(1080, 1920), Vector2(0, 1920)]),
    ]
    for i in range(facets.size()):
        var base_color: Color = surface if i % 2 == 0 else input_color
        draw_colored_polygon(facets[i], Color(base_color, (0.16 + float(i % 3) * 0.035) * strength))

    # Gold veins move only a few pixels, like reflected light on stone.
    var glint: float = sin(pulse_time * 0.32) * 6.0
    var veins: Array[PackedVector2Array] = [
        PackedVector2Array([Vector2(30, 760), Vector2(390, 620), Vector2(720, 690), Vector2(1050, 485)]),
        PackedVector2Array([Vector2(392, 624), Vector2(520, 1290), Vector2(1080, 1680)]),
        PackedVector2Array([Vector2(720, 690), Vector2(650, 1350), Vector2(1080, 1430)]),
        PackedVector2Array([Vector2(95, 1540), Vector2(520, 1290), Vector2(655, 1352)]),
    ]
    for i in range(veins.size()):
        var shifted := PackedVector2Array()
        for p in veins[i]:
            shifted.append(p + Vector2(glint * float((i % 2) * 2 - 1), 0))
        draw_polyline(shifted, Color(accent2, (0.16 + float(i) * 0.025) * strength), 2.0 + float(i % 2), true)
        if i < 2:
            draw_polyline(shifted, Color(accent, 0.07 * strength), 7.0, true)

    # Metallic shards catch a slow moving highlight.
    for i in range(11):
        var x: float = 65.0 + fmod(float(i * 197), 950.0)
        var y: float = 220.0 + fmod(float(i * 271), 1450.0)
        var lift: float = sin(pulse_time * 0.19 + float(i)) * 9.0
        var shard := PackedVector2Array([
            Vector2(x, y + lift),
            Vector2(x + 18.0 + float(i % 4) * 5.0, y + 42.0 + lift),
            Vector2(x - 9.0, y + 68.0 + lift),
        ])
        draw_colored_polygon(shard, Color(accent2, (0.08 + float(i % 3) * 0.025) * strength))
        draw_line(shard[0], shard[1], Color(1.0, 0.92, 0.62, 0.22 * strength), 1.4, true)

    # Wide diagonal light sweep across the obsidian facets.
    var sweep_x: float = -500.0 + fmod(pulse_time * 75.0, 2100.0)
    var sweep := PackedVector2Array([
        Vector2(sweep_x, -80),
        Vector2(sweep_x + 120, -80),
        Vector2(sweep_x + 780, 2000),
        Vector2(sweep_x + 620, 2000),
    ])
    draw_colored_polygon(sweep, Color(accent2, 0.025 * strength))

func _draw_polar_aurora(colors: Dictionary, strength: float) -> void:
    var accent: Color = colors["accent"]
    var accent2: Color = colors["accent2"]
    var text_color: Color = colors["text"]
    var surface: Color = colors["surface"]

    # Sparse cold-sky stars drawn as diamonds.
    for i in range(42):
        var x: float = fmod(float(i * 223 + 37), 1080.0)
        var y: float = fmod(float(i * 179 + 83), 1120.0)
        var twinkle: float = 0.08 + 0.10 * (0.5 + 0.5 * sin(pulse_time * 0.55 + float(i) * 0.61))
        _draw_diamond(Vector2(x, y), 1.8 + float(i % 3) * 0.7, Color(text_color, twinkle * strength))

    # Wide filled curtains with layered sine motion, not skinny neon lines.
    for ribbon in range(5):
        var top := PackedVector2Array()
        var bottom := PackedVector2Array()
        var base_y: float = 180.0 + float(ribbon) * 175.0
        var thickness: float = 145.0 + float(ribbon) * 22.0
        for step in range(24):
            var x: float = -100.0 + float(step) * 56.0
            var phase: float = float(step) * 0.43 + pulse_time * (0.16 + float(ribbon) * 0.018)
            var wave: float = sin(phase) * (50.0 + float(ribbon) * 7.0) + sin(phase * 0.47 + 1.6) * 28.0
            top.append(Vector2(x, base_y + wave))
            bottom.append(Vector2(x, base_y + wave + thickness + sin(phase * 0.73) * 22.0))

        var curtain := PackedVector2Array()
        for p in top:
            curtain.append(p)
        for idx in range(bottom.size() - 1, -1, -1):
            curtain.append(bottom[idx])

        var ribbon_color: Color = accent if ribbon % 2 == 0 else accent2
        var alpha: float = (0.040 + float(ribbon % 3) * 0.012) * strength
        draw_colored_polygon(curtain, Color(ribbon_color, alpha))
        draw_polyline(top, Color(ribbon_color, 0.16 * strength), 2.2, true)

    # Layered distant mountains anchor the scene.
    var mountain_back := PackedVector2Array([
        Vector2(0, 1480), Vector2(150, 1300), Vector2(300, 1435), Vector2(455, 1240),
        Vector2(610, 1410), Vector2(770, 1190), Vector2(930, 1370), Vector2(1080, 1260),
        Vector2(1080, 1920), Vector2(0, 1920),
    ])
    var mountain_front := PackedVector2Array([
        Vector2(0, 1640), Vector2(185, 1490), Vector2(355, 1580), Vector2(535, 1410),
        Vector2(705, 1590), Vector2(895, 1450), Vector2(1080, 1540),
        Vector2(1080, 1920), Vector2(0, 1920),
    ])
    draw_colored_polygon(mountain_back, Color(surface, 0.34 * strength))
    draw_colored_polygon(mountain_front, Color(colors["bg"], 0.62 * strength))
    draw_polyline(PackedVector2Array([Vector2(0, 1640), Vector2(185, 1490), Vector2(355, 1580), Vector2(535, 1410), Vector2(705, 1590), Vector2(895, 1450), Vector2(1080, 1540)]), Color(accent2, 0.10 * strength), 1.5, true)

func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array([
        center + Vector2(0, -radius),
        center + Vector2(radius, 0),
        center + Vector2(0, radius),
        center + Vector2(-radius, 0),
    ])
    draw_colored_polygon(points, color)
