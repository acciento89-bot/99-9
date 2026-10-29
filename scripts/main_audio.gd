extends "res://scripts/main_practice.gd"
const PrecisionAudio = preload("res://scripts/audio_service.gd")
var _audio: Node
var _audio_settings_scroll: ScrollContainer
var _audio_settings_canvas: Control
var _audio_settings_back: Button
var _audio_music_button: Button
var _audio_sound_button: Button
var _audio_status: Label
var _audio_panel: Panel
var _audio_title: Label
var _audio_original_card_y: Dictionary = {}

func _audio_settings_path() -> String:
    return "user://audio-v1.cfg"

func _ready() -> void:
    _audio = PrecisionAudio.new()
    _audio.name = "PrecisionAudio"
    _audio.settings_path = _audio_settings_path()
    add_child(_audio)
    super._ready()
    get_viewport().size_changed.connect(_audio_layout_settings)
    _audio_layout_settings()

func _make_button(text_value: String, minimum: Vector2, font_size: int = 30, role: String = "secondary") -> Button:
    var button := super._make_button(text_value, minimum, font_size, role)
    button.pressed.connect(func() -> void:
        if _audio != null: _audio.play_ui())
    return button

func _build_settings_ui() -> void:
    super._build_settings_ui()
    _audio_settings_scroll = PracticeTouchScroll.new()
    _audio_settings_scroll.name = "SettingsScroll"
    _audio_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    settings_layer.add_child(_audio_settings_scroll)
    var content := Control.new()
    content.custom_minimum_size = Vector2(1080, 1755)
    _audio_settings_scroll.add_child(content)
    _audio_settings_canvas = Control.new()
    _audio_settings_canvas.size = Vector2(1080, 1755)
    content.add_child(_audio_settings_canvas)
    # Keep all real original cards, callbacks and nested controls intact.
    for child in settings_layer.get_children():
        if child is Panel and child.position.y >= 330:
            child.reparent(_audio_settings_canvas)
            child.position.y -= 30
            _audio_original_card_y[child] = child.position.y
        elif child is Button and child.text == "BACK":
            _audio_settings_back = child
    _audio_panel = _make_panel("soft")
    _place(_audio_panel, Vector2(130, 20), Vector2(820, 280), _audio_settings_canvas)
    _audio_title = _make_label("AUDIO", 31, HORIZONTAL_ALIGNMENT_LEFT)
    _place(_audio_title, Vector2(45, 20), Vector2(720, 50), _audio_panel)
    _audio_music_button = _make_button("", Vector2(345, 100), 28, "secondary")
    _audio_music_button.name = "MusicSwitch"
    _place(_audio_music_button, Vector2(45, 90), Vector2(345, 100), _audio_panel)
    _audio_music_button.pressed.connect(func() -> void: _audio.set_music_enabled(not _audio.music_enabled))
    _audio_sound_button = _make_button("", Vector2(345, 100), 28, "secondary")
    _audio_sound_button.name = "SoundSwitch"
    _place(_audio_sound_button, Vector2(430, 90), Vector2(345, 100), _audio_panel)
    _audio_sound_button.pressed.connect(func() -> void: _audio.set_sound_enabled(not _audio.sound_enabled))
    _audio_status = _make_muted_label("", 20, HORIZONTAL_ALIGNMENT_LEFT)
    _place(_audio_status, Vector2(45, 210), Vector2(730, 50), _audio_panel)
    _audio_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _audio.settings_changed.connect(_audio_refresh_settings)
    _audio_refresh_settings()

func _audio_refresh_settings() -> void:
    _audio_music_button.text = "MUSIC: " + ("ON" if _audio.music_enabled else "OFF")
    _audio_sound_button.text = "SOUND: " + ("ON" if _audio.sound_enabled else "OFF")
    _audio_status.text = "NOT SAVED — please try again." if _audio.save_error else "Quiet original synth loop · sound effects separate"

func _audio_layout_settings() -> void:
    if _audio_settings_scroll == null: return
    var viewport := get_viewport_rect().size
    # A headless/initializing viewport may report 64x64 before its real size.
    if viewport.x < 240 or viewport.y < 360: return
    var factor := minf(1.0, (viewport.x - 24) / 1080.0)
    var button_height := maxf(100, 48.0 * _practice_unit / factor)
    var status_height := maxf(50, 36.0 * _practice_unit / factor)
    var stacked := viewport.x < 480
    var stack_extra := button_height + 20 if stacked else 0.0
    var extra := button_height - 100 + status_height - 50 + stack_extra
    for button in [_audio_music_button, _audio_sound_button]:
        button.add_theme_font_size_override("font_size", int(maxf(28, 16 * _practice_unit / factor)))
        button.custom_minimum_size = Vector2(730 if stacked else 345, button_height)
        button.size = button.custom_minimum_size
    _audio_sound_button.position = Vector2(45, 110 + button_height) if stacked else Vector2(430, 90)
    _audio_title.add_theme_font_size_override("font_size", int(maxf(31, 18 * _practice_unit / factor)))
    _audio_status.add_theme_font_size_override("font_size", int(maxf(20, 12 * _practice_unit / factor)))
    _audio_status.position.y = 110 + button_height + stack_extra
    _audio_status.size.y = status_height
    _audio_panel.size.y = 280 + extra
    for card in _audio_original_card_y:
        card.position.y = _audio_original_card_y[card] + extra
    var top := maxf(315, 330 * factor)
    _audio_settings_scroll.position = Vector2(0, top)
    _audio_settings_scroll.size = Vector2(viewport.x, maxf(1, viewport.y - top - 24))
    _audio_settings_canvas.scale = Vector2.ONE * factor
    _audio_settings_canvas.size.y = 1755 + extra
    _audio_settings_scroll.get_child(0).custom_minimum_size = Vector2(1080, 1755 + extra) * factor

func _stop_round() -> void:
    super._stop_round()
    _audio.play_result(result_value >= STREAK_THRESHOLD)

func _practice_commit(proposed: Dictionary, kind: String) -> bool:
    var previous: int = 0 if _practice_book.active == null else _practice_book.active.outcomes.size()
    var saved := super._practice_commit(proposed, kind)
    if saved and kind == "record" and _practice_book.active != null and _practice_book.active.outcomes.size() > previous:
        _audio.play_result(bool(_practice_book.active.outcomes.back().hit))
    return saved

func _notification(what: int) -> void:
    # Godot delivers _notification to every script in the inheritance chain.
    # Explicit super here would checkpoint Practice twice for one OS event.
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
        # Music may return on foreground; both game modes still require Resume.
        if _practice_initialized and not _practice_open: _pause_game()
