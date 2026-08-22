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
