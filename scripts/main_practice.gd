extends "res://scripts/main_v10.gd"
const Practice = preload("res://scripts/practice_model.gd")
const PracticeArchive = preload("res://scripts/practice_archive.gd")

var _practice_book: Dictionary = Practice.empty_book()
var _practice_round: Dictionary = {}
var _practice_pending: Dictionary = {}
var _practice_pending_kind := ""
var _practice_store
var _practice_error := ""
var _practice_open := false
var _practice_initialized := false
var _practice_de := OS.get_locale_language() == "de"
var _practice_focused := true
var _practice_view := "ladder"
var _practice_last_tick: int = 0
var _practice_last_checkpoint: int = 0
var _practice_layout_poll := 0.0
var _practice_entry: Button
var _practice_layer: Control
var _practice_panel: PanelContainer
var _practice_scroll: ScrollContainer
var _practice_content: VBoxContainer
var _practice_title: Label
var _practice_status: Label
var _practice_value: Label
var _practice_meter: ProgressBar
var _practice_unit := 1.0

func _practice_now() -> int:
    return Time.get_ticks_usec()

func _practice_archive_path() -> String:
    return "user://practice-v1.json"

func _ready() -> void:
    super._ready()
    _practice_store = PracticeArchive.new(_practice_archive_path())
    _practice_load()
    _practice_entry = Button.new()
    _practice_entry.name = "PrecisionPracticeEntry"
    _practice_entry.text = "PRÄZISIONSTRAINING / PRECISION PRACTICE"
    _practice_entry.pressed.connect(_practice_open_menu)
    add_child(_practice_entry)
    _practice_layer = Control.new()
    _practice_layer.name = "PrecisionPractice"
    _practice_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _practice_layer.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_practice_layer)
    var shade := ColorRect.new()
    shade.color = Color(.008, .014, .028, .99)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _practice_layer.add_child(shade)
    _practice_panel = PanelContainer.new()
    _practice_layer.add_child(_practice_panel)
    _practice_scroll = ScrollContainer.new()
    _practice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _practice_panel.add_child(_practice_scroll)
    _practice_content = VBoxContainer.new()
    _practice_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _practice_scroll.add_child(_practice_content)
    _practice_initialized = true
    _practice_layer.visible = false
    get_viewport().size_changed.connect(_practice_layout)
    _practice_layout()
    _practice_entry_visibility()

func _practice_t(de: String, en: String) -> String:
    return de if _practice_de else en

func _practice_load() -> void:
    var loaded: Dictionary = _practice_store.read_book()
    if not loaded.ok:
        _practice_error = str(loaded.error)
        return
    _practice_book = loaded.book
    _practice_error = ""
    _practice_pending = {}
    _practice_round = {}
    if _practice_book.active != null:
        _practice_round = _practice_book.active.round.duplicate(true)
        # A cold process never silently resumes a running cursor.
        if _practice_round.state == "running":
            _practice_round = Practice.tick(_practice_round, 0.0, false).round
    _practice_last_tick = 0

func _show_screen(target: AppScreen) -> void:
    super._show_screen(target)
    if _practice_initialized: _practice_entry_visibility()

func _apply_theme_to_controls() -> void:
    super._apply_theme_to_controls()
    if _practice_initialized:
        _practice_style_button(_practice_entry)
        if _practice_open: _practice_render()

func _practice_entry_visibility() -> void:
    if not _practice_initialized: return
    _practice_entry.visible = not _practice_open and screen == AppScreen.MENU and not achievements_open
    _practice_entry.disabled = waiting_for_interstitial_close

func _practice_open_menu() -> void:
    if waiting_for_interstitial_close: return
    _practice_open = true
    _practice_view = "ladder"
    super._show_screen(AppScreen.MENU)
    menu_layer.visible = false
    _practice_layer.visible = true
    _practice_entry_visibility()
    _practice_render()

func _practice_commit(proposed: Dictionary, kind: String) -> bool:
    var saved: Dictionary = _practice_store.save_book(proposed, int(_practice_book.revision))
    if not saved.ok:
        _practice_pending = proposed.duplicate(true)
        _practice_pending_kind = kind
        _practice_error = str(saved.error)
        _practice_last_tick = 0
        _practice_render()
        return false
    _practice_book = proposed
    _practice_pending = {}
    _practice_error = ""
    if _practice_book.active != null: _practice_round = _practice_book.active.round.duplicate(true)
    if kind == "begin" or kind == "next": _practice_view = "run"
    if kind == "abandon": _practice_view = "ladder"
    _practice_last_checkpoint = _practice_now()
    # A synchronous save may hold the rendered cursor; exclude its I/O time.
    if not _practice_round.is_empty() and _practice_round.state == "running": _practice_last_tick = _practice_last_checkpoint
    if kind != "tick": _practice_render()
    return true

func _practice_begin(stage: int) -> void:
    if not _practice_pending.is_empty() or not _practice_error.is_empty(): return
    var response: Dictionary = Practice.begin(_practice_book, stage, _make_uuid(), _make_uuid())
    if response.ok: _practice_commit(response.book, "begin")

func _practice_open_active() -> void:
    _practice_view = "run"
    _practice_render()

func _practice_action() -> void:
    if not _practice_pending.is_empty() or not _practice_error.is_empty() or _practice_book.active == null: return
    if _practice_round.state == "ready":
        var started: Dictionary = Practice.start_round(_practice_round)
        if not started.ok: return
        var checkpoint: Dictionary = Practice.checkpoint(_practice_book, _practice_book.active.session_id, _practice_round.id, started.round)
        if checkpoint.ok and _practice_commit(checkpoint.book, "start"):
            _practice_round = Practice.tick(_practice_round, 0.0, true).round
            _practice_last_tick = _practice_now()
    elif _practice_round.state == "running" or _practice_round.state == "expired":
        _practice_tick_now()
        var response: Dictionary = Practice.record(_practice_book, _practice_book.active.session_id, _practice_round.id, float(_practice_round.phase))
        if response.ok: _practice_commit(response.book, "record")
        _practice_last_tick = 0

func _practice_next() -> void:
    if not _practice_pending.is_empty() or not _practice_error.is_empty() or _practice_book.active == null: return
    var response: Dictionary = Practice.next_round(_practice_book, _practice_book.active.session_id, _practice_round.id, _make_uuid())
    if response.ok: _practice_commit(response.book, "next")

func _practice_tick_now() -> void:
    if _practice_round.is_empty() or _practice_round.state != "running" or not _practice_focused: return
    var now := _practice_now()
    var delta := 0.0 if _practice_last_tick == 0 else float(maxi(0, now - _practice_last_tick)) / 1000000.0
    _practice_last_tick = now
    var response: Dictionary = Practice.tick(_practice_round, delta, true)
    if response.ok: _practice_round = response.round

func _practice_pause() -> void:
    if _practice_round.is_empty() or _practice_round.state != "running" or not _practice_pending.is_empty(): return
    _practice_tick_now()
    if _practice_round.state == "expired":
        _practice_action()
        return
    var paused: Dictionary = Practice.tick(_practice_round, 0.0, false)
    if not paused.ok: return
    _practice_round = paused.round
    _practice_last_tick = 0
    var response: Dictionary = Practice.checkpoint(_practice_book, _practice_book.active.session_id, _practice_round.id, _practice_round)
    if response.ok: _practice_commit(response.book, "pause")

func _practice_resume() -> void:
    if not _practice_pending.is_empty() or not _practice_error.is_empty() or not _practice_focused: return
    var resumed: Dictionary = Practice.resume_round(_practice_round)
    if not resumed.ok: return
    var response: Dictionary = Practice.checkpoint(_practice_book, _practice_book.active.session_id, _practice_round.id, resumed.round)
    if response.ok and _practice_commit(response.book, "resume"):
        _practice_round = Practice.tick(_practice_round, 0.0, true).round
        _practice_last_tick = _practice_now()

func _practice_exit() -> void:
    _practice_pause()
    _practice_open = false
    _practice_layer.visible = false
    _practice_last_tick = 0
    super._show_screen(AppScreen.MENU)
    _practice_entry_visibility()

func _practice_retry() -> void:
    if not _practice_pending.is_empty():
        _practice_commit(_practice_pending, _practice_pending_kind)
        # A successfully retried start/resume still requires an explicit resume;
        # no save failure interval becomes meter time.
        if _practice_error.is_empty() and _practice_round.state == "running":
            _practice_round = Practice.tick(_practice_round, 0.0, false).round
            _practice_render()
    else:
        _practice_load()
        _practice_render()

func _practice_reload() -> void:
    _practice_load()
    _practice_view = "ladder"
    _practice_render()

func _practice_abandon() -> void:
    if _practice_book.active == null or not _practice_pending.is_empty(): return
    var response: Dictionary = Practice.abandon(_practice_book, _practice_book.active.session_id)
    if response.ok: _practice_commit(response.book, "abandon")

func _process(delta: float) -> void:
    super._process(delta)
    if not _practice_initialized: return
    _practice_entry_visibility()
    _practice_layout_poll += delta
    if _practice_layout_poll >= .5:
        _practice_layout_poll = 0.0
        _practice_layout()
    if not _practice_open or not _practice_pending.is_empty() or not _practice_error.is_empty(): return
    _practice_tick_now()
    if not _practice_round.is_empty() and _practice_round.state == "expired": _practice_action()
    if not _practice_round.is_empty() and _practice_round.state == "running" and _practice_now() - _practice_last_checkpoint >= 2000000:
        var checkpoint: Dictionary = Practice.checkpoint(_practice_book, _practice_book.active.session_id, _practice_round.id, _practice_round)
        if checkpoint.ok: _practice_commit(checkpoint.book, "tick")
    _practice_update_meter()

func _notification(what: int) -> void:
    if not _practice_initialized: return
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
        # Capture the foreground boundary before marking it inactive.
        if _practice_open: _practice_pause()
        _practice_focused = false
    elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
        _practice_focused = true
        _practice_last_tick = 0
        _practice_layout()

func _practice_safe_rect() -> Rect2:
    var bounds := Rect2(Vector2.ZERO, get_viewport_rect().size)
    if DisplayServer.get_name() == "headless": return bounds
    var native := Rect2(DisplayServer.get_display_safe_area())
    if native.size.x <= 0 or native.size.y <= 0: return bounds
    var converted: Rect2 = get_screen_transform().affine_inverse() * native
    var available := bounds.intersection(converted)
    return available if available.size.x > 0 and available.size.y > 0 else bounds

func _practice_layout() -> void:
    if not _practice_initialized: return
    var native_scale := 1.0
    if DisplayServer.get_name() != "headless":
        native_scale = maxf(1.0, DisplayServer.screen_get_scale())
        if OS.get_name() == "Android": native_scale = maxf(native_scale, float(DisplayServer.screen_get_dpi()) / 160.0)
    var transform_scale := get_screen_transform().get_scale()
    _practice_unit = native_scale / maxf(.001, minf(absf(transform_scale.x), absf(transform_scale.y)))
    var available := _practice_safe_rect()
    var margin := 12.0 * _practice_unit
    var width := maxf(1.0, available.size.x - margin * 2.0)
    _practice_entry.position = Vector2(available.position.x + margin, available.end.y - margin - 64.0 * _practice_unit)
    _practice_entry.size = Vector2(width, 64.0 * _practice_unit)
    _practice_style_button(_practice_entry)
    var panel_width := minf(width, 560.0 * _practice_unit)
    _practice_panel.position = Vector2(available.get_center().x - panel_width / 2.0, available.position.y + margin)
    _practice_panel.size = Vector2(panel_width, maxf(1, available.size.y - margin * 2.0))
    _practice_content.add_theme_constant_override("separation", int(12 * _practice_unit))
    var paper := _outlined_box(_theme_colors(active_theme_id).surface, _theme_colors(active_theme_id).border, int(16 * _practice_unit), 1)
    paper.content_margin_left = margin
    paper.content_margin_right = margin
    paper.content_margin_top = margin
    paper.content_margin_bottom = margin
    _practice_panel.add_theme_stylebox_override("panel", paper)
    for control in _practice_content.get_children():
        if control is Button: _practice_style_button(control)
        elif control is Label: control.add_theme_font_size_override("font_size", int((26 if control == _practice_title else 18) * _practice_unit))
    if is_instance_valid(_practice_meter): _practice_meter.custom_minimum_size.y = 36 * _practice_unit

func _practice_style_button(button: Button) -> void:
    var colors := _theme_colors(active_theme_id)
    button.custom_minimum_size.y = 64 * _practice_unit
    button.add_theme_font_size_override("font_size", int(18 * _practice_unit))
    button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    button.add_theme_color_override("font_color", colors.text)
    button.add_theme_stylebox_override("normal", _outlined_box(colors.surface2, colors.border, int(10 * _practice_unit), 1))
    button.add_theme_stylebox_override("pressed", _outlined_box(colors.accent, colors.accent2, int(10 * _practice_unit), 2))
    button.add_theme_stylebox_override("focus", _outlined_box(colors.surface2, colors.accent2, int(10 * _practice_unit), 2))

func _practice_label(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_color", _theme_colors(active_theme_id).text)
    _practice_content.add_child(label)
    return label

func _practice_button(text: String, action: Callable, enabled: bool = true) -> Button:
    var button := Button.new()
    button.text = text
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
    button.pressed.connect(action)
    button.disabled = not enabled
    _practice_content.add_child(button)
    _practice_style_button(button)
    return button

func _practice_direction(definition: Dictionary) -> String:
    if definition.direction == "peak": return _practice_t("SCHEITEL", "PEAK")
    return _practice_t("STEIGEND ↑", "RISING ↑") if definition.direction == "rising" else _practice_t("FALLEND ↓", "FALLING ↓")

func _practice_render() -> void:
    if not _practice_initialized: return
    for child in _practice_content.get_children():
        _practice_content.remove_child(child)
        child.queue_free()
    _practice_value = null
    _practice_meter = null
    _practice_title = _practice_label(_practice_t("PRÄZISIONSTRAINING", "PRECISION PRACTICE"))
    _practice_status = _practice_label("")
    if not _practice_error.is_empty():
        _practice_status.text = _practice_t("Nicht gespeichert. Vorhandene Daten bleiben erhalten. Du kannst das normale Spiel weiter nutzen.", "Not saved. Existing data is preserved. Normal play remains available.")
        _practice_button(_practice_t("ERNEUT VERSUCHEN", "RETRY SAVE"), _practice_retry)
        if not _practice_pending.is_empty(): _practice_button(_practice_t("GESPEICHERTEN STAND LADEN · UNGESPEICHERTE ÄNDERUNG VERWERFEN", "LOAD SAVED STATE · DISCARD UNSAVED CHANGE"), _practice_reload)
    elif _practice_view == "run" and _practice_book.active != null:
        _practice_render_run()
    else:
        _practice_render_ladder()
    _practice_button(_practice_t("SPRACHE: DEUTSCH", "LANGUAGE: ENGLISH"), func() -> void:
        _practice_de = not _practice_de
        _practice_render()
    )
    _practice_button(_practice_t("‹ HAUPTMENÜ", "‹ MAIN MENU"), _practice_exit)
    _practice_layout()

func _practice_render_ladder() -> void:
    _practice_status.text = _practice_t("12 Versuche je Sitzung. 8 Treffer öffnen die nächste Stufe. Eigene Übungsrekorde: Arcade-Punkte, Serien und Ranglisten bleiben getrennt.", "12 attempts per session. 8 hits open the next stage. Separate practice records: arcade scores, streaks and rankings stay separate.")
    var active = _practice_book.active
    if active != null and active.state == "active":
        _practice_button(_practice_t("SITZUNG FORTSETZEN · STUFE ", "CONTINUE SESSION · STAGE ") + str(active.stage), _practice_open_active)
        _practice_button(_practice_t("UNVOLLSTÄNDIGE SITZUNG BEENDEN", "END INCOMPLETE SESSION"), _practice_abandon)
    for definition in Practice.catalog():
        var stage := int(definition.id)
        var detail := ""
        for record_value in _practice_book.records:
            if record_value.stage == stage:
                detail = _practice_t("\nBestes Ergebnis: ", "\nBest session: ") + str(record_value.best.hits) + "/12 · " + ("%.2f ms" % record_value.best.mean_abs_ms)
        _practice_button(str(stage) + " · %.3f%% · " % definition.target + _practice_direction(definition) + detail, _practice_begin.bind(stage), Practice.unlocked(_practice_book, stage) and (active == null or active.state != "active"))
        if not detail.is_empty():
            for record_value in _practice_book.records:
                if record_value.stage != stage: continue
                var recent := _practice_t("Letzte Sitzungen: ", "Recent sessions: ")
                for summary_value in record_value.history: recent += str(summary_value.hits) + "/12 · "
                _practice_label(recent.trim_suffix(" · "))

func _practice_render_run() -> void:
    var active: Dictionary = _practice_book.active
    var definition: Dictionary = Practice.catalog()[int(active.stage) - 1]
    var number: int = active.outcomes.size() if _practice_round.state == "result" else active.outcomes.size() + 1
    _practice_status.text = _practice_t("STUFE ", "STAGE ") + str(active.stage) + " · " + _practice_direction(definition) + "\n" + _practice_t("Ziel: ", "Target: ") + "%.3f%% · ±%.3f%%\n" % [definition.target, definition.window] + _practice_t("Versuch ", "Attempt ") + str(mini(12, number)) + "/12"
    _practice_value = _practice_label("")
    _practice_meter = ProgressBar.new()
    _practice_meter.max_value = 100
    _practice_meter.show_percentage = false
    _practice_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _practice_content.add_child(_practice_meter)
    _practice_meter.draw.connect(func() -> void:
        if not is_instance_valid(_practice_meter): return
        var x: float = _practice_meter.size.x * float(definition.target) / 100.0
        _practice_meter.draw_line(Vector2(x, 0), Vector2(x, _practice_meter.size.y), _theme_colors(active_theme_id).premium, maxf(2, 2 * _practice_unit))
    )
    if _practice_round.state == "result":
        var outcome: Dictionary = active.outcomes.back()
        _practice_label((_practice_t("TREFFER", "HIT") if outcome.hit else _practice_t("DANEBEN", "MISS")) + " · " + _practice_timing(outcome))
        _practice_label(_practice_t("Zeit relativ zum angegebenen ersten Zieldurchgang. Ein Treffer auf der falschen Richtung zählt nicht.", "Timing is relative to the specified first target crossing. A hit on the wrong direction does not count."))
        if active.state == "complete":
            var summary: Dictionary = Practice._summary(active.session_id, active.outcomes)
            _practice_label(_practice_t("GESPEICHERT · ", "SAVED · ") + str(summary.hits) + "/12 · " + ("%.2f ms" % summary.mean_abs_ms) + _practice_t(" mittlere Abweichung", " mean absolute error"))
            _practice_button(_practice_t("ZUR STUFENÜBERSICHT", "BACK TO STAGES"), _practice_open_menu)
        else: _practice_button(_practice_t("NÄCHSTER VERSUCH", "NEXT ATTEMPT"), _practice_next)
        for index in range(active.outcomes.size() - 1, -1, -1):
            var prior: Dictionary = active.outcomes[index]
            _practice_label(str(index + 1) + " · %.3f%% · " % prior.value + _practice_timing(prior))
    elif _practice_round.state == "paused":
        _practice_label(_practice_t("PAUSIERT · Zeiger bleibt stehen. Fortsetzen startet ausdrücklich hier.", "PAUSED · The cursor is held. Resume explicitly from here."))
        _practice_button(_practice_t("FORTSETZEN", "RESUME"), _practice_resume)
    else:
        _practice_button(_practice_t("START", "START") if _practice_round.state == "ready" else _practice_t("JETZT STOPPEN", "STOP NOW"), _practice_action)
        if _practice_round.state == "running": _practice_button(_practice_t("PAUSE", "PAUSE"), _practice_pause)
    _practice_update_meter()

func _practice_timing(outcome: Dictionary) -> String:
    var word := _practice_t("PUNKTGENAU", "ON TIME")
    if outcome.timing == "early": word = _practice_t("ZU FRÜH", "EARLY")
    elif outcome.timing == "late": word = _practice_t("ZU SPÄT", "LATE")
    return word + " %+.2f ms" % float(outcome.signed_ms)

func _practice_update_meter() -> void:
    if not is_instance_valid(_practice_value) or not is_instance_valid(_practice_meter) or _practice_round.is_empty(): return
    var value: float = 50.0 - 50.0 * cos(float(_practice_round.phase))
    _practice_value.text = "%.3f%% " % value + ("↑" if _practice_round.phase <= PI else "↓")
    _practice_meter.value = value
    _practice_meter.queue_redraw()
