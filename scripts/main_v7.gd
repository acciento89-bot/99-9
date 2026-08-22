extends "res://scripts/main_v6.gd"

# Build 8: consent-aware AdMob test integration.
# Ads are intentionally limited to natural breaks between rounds.

const FIRST_INTERSTITIAL_AFTER_ROUNDS := 6
const INTERSTITIAL_INTERVAL_ROUNDS := 7
const INTERSTITIAL_COOLDOWN_MS := 120000

@onready var ads_service: Node = $AdsService

var rounds_since_interstitial := 0
var interstitial_has_shown := false
var last_interstitial_ms := 0
var waiting_for_interstitial_close := false


func _ready() -> void:
    super._ready()
    ads_service.interstitial_closed.connect(_on_interstitial_closed)
    ads_service.ad_error.connect(_on_ad_error)
    ads_service.start_ads()


func _build_settings_ui() -> void:
    super._build_settings_ui()

    var privacy_panel := _make_panel("soft")
    _place(privacy_panel, Vector2(130, 1200), Vector2(820, 245), settings_layer)

    var privacy_title := _make_label("AD PRIVACY", 31, HORIZONTAL_ALIGNMENT_LEFT)
    _place(privacy_title, Vector2(45, 30), Vector2(360, 55), privacy_panel)

    var privacy_desc := _make_muted_label("Review or change your advertising consent for this device.", 19, HORIZONTAL_ALIGNMENT_LEFT)
    _place(privacy_desc, Vector2(45, 85), Vector2(500, 80), privacy_panel)
    privacy_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var privacy_button := _make_button("PRIVACY OPTIONS", Vector2(220, 82), 22, "secondary")
    _place(privacy_button, Vector2(555, 82), Vector2(220, 82), privacy_panel)
    privacy_button.pressed.connect(func() -> void: ads_service.show_privacy_options())


func _stop_round() -> void:
    super._stop_round()
    rounds_since_interstitial += 1


func _next_round() -> void:
    if waiting_for_interstitial_close:
        return

    if _is_interstitial_due() and ads_service.show_interstitial_if_ready():
        waiting_for_interstitial_close = true
        return

    _advance_to_next_round()


func _advance_to_next_round() -> void:
    round_number += 1
    _start_round()


func _is_interstitial_due() -> bool:
    if not interstitial_has_shown:
        return rounds_since_interstitial >= FIRST_INTERSTITIAL_AFTER_ROUNDS

    if rounds_since_interstitial < INTERSTITIAL_INTERVAL_ROUNDS:
        return false

    return Time.get_ticks_msec() - last_interstitial_ms >= INTERSTITIAL_COOLDOWN_MS


func _on_interstitial_closed() -> void:
    if not waiting_for_interstitial_close:
        return

    waiting_for_interstitial_close = false
    interstitial_has_shown = true
    rounds_since_interstitial = 0
    last_interstitial_ms = Time.get_ticks_msec()
    _advance_to_next_round()


func _on_ad_error(message: String) -> void:
    # Ads must never block core gameplay. Errors stay diagnostic only.
    print("99.9 AdMob: ", message)
