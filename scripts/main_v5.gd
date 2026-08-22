extends "res://scripts/main_v4.gd"

# Build 5: real premium theme store flow. Gameplay remains inherited from Build 4.

@onready var iap_service: Node = $IapService

var store_prices: Dictionary = {}
var store_connected := false
var restore_button: Button

func _ready() -> void:
    super._ready()

    restore_button = _make_button("RESTORE PURCHASES", Vector2(430, 76), 23, "ghost")
    _place(restore_button, Vector2(325, 1585), Vector2(430, 76), themes_layer)
    restore_button.disabled = true
    restore_button.pressed.connect(_restore_purchases)

    iap_service.store_state_changed.connect(_on_store_state_changed)
    iap_service.products_updated.connect(_on_store_products_updated)
    iap_service.entitlements_updated.connect(_on_store_entitlements_updated)
    iap_service.purchase_completed.connect(_on_store_purchase_completed)
    iap_service.purchase_failed.connect(_on_store_purchase_failed)
    iap_service.restore_completed.connect(_on_store_restore_completed)
    iap_service.restore_failed.connect(_on_store_restore_failed)

    _apply_theme_to_controls()
    _refresh_theme_screen()
    iap_service.start_store()

func _activate_preview_theme() -> void:
    if _is_theme_owned(preview_theme_id):
        super._activate_preview_theme()
        return

    var price := iap_service.get_display_price(preview_theme_id)
    if not store_connected or price.is_empty():
        theme_status_label.text = "STORE IS STILL LOADING · TRY AGAIN IN A MOMENT"
        return

    theme_action_button.disabled = true
    restore_button.disabled = true
    theme_action_button.text = "OPENING STORE..."
    theme_status_label.text = "CONFIRM %s IN THE APP STORE" % _theme_name(preview_theme_id)
    iap_service.purchase_theme(preview_theme_id)

func _refresh_theme_screen() -> void:
    super._refresh_theme_screen()
    if theme_preview_title == null:
        return

    var owned := _is_theme_owned(preview_theme_id)
    var equipped := preview_theme_id == selected_theme_id
    if equipped:
        theme_action_button.disabled = true
    elif owned:
        theme_action_button.disabled = false
    else:
        var price := str(store_prices.get(preview_theme_id, ""))
        if price.is_empty():
            theme_preview_detail.text = "PREMIUM · STORE PRICE LOADING"
            theme_action_button.text = "CONNECTING TO STORE..."
            theme_action_button.disabled = true
        else:
            theme_preview_detail.text = "PREMIUM · %s · ONE-TIME PURCHASE" % price
            theme_action_button.text = "UNLOCK · %s" % price
            theme_action_button.disabled = false

    if restore_button != null:
        restore_button.disabled = not store_connected

func _on_store_state_changed(ready: bool, message: String) -> void:
    store_connected = ready
    if restore_button != null:
        restore_button.disabled = not ready
    if screen == AppScreen.THEMES and not ready:
        theme_status_label.text = message.to_upper()
    _refresh_theme_screen()

func _on_store_products_updated(prices: Dictionary) -> void:
    store_prices = prices.duplicate()
    _refresh_theme_screen()
    if screen == AppScreen.THEMES:
        theme_status_label.text = "STORE READY · PREMIUM DESIGNS ARE PERMANENT UNLOCKS"

func _on_store_entitlements_updated(theme_ids: Array[String]) -> void:
    var changed := false
    for theme_id in theme_ids:
        if THEME_IDS.has(theme_id) and theme_id != "midnight" and not owned_themes.has(theme_id):
            owned_themes.append(theme_id)
            changed = true
    if changed:
        _save()
    _refresh_theme_screen()

func _on_store_purchase_completed(theme_id: String) -> void:
    if not THEME_IDS.has(theme_id) or theme_id == "midnight":
        return
    if not owned_themes.has(theme_id):
        owned_themes.append(theme_id)
    selected_theme_id = theme_id
    preview_theme_id = theme_id
    active_theme_id = theme_id
    _save()
    _apply_theme_to_controls()
    _refresh_theme_screen()
    theme_action_button.disabled = true
    restore_button.disabled = not store_connected
    theme_status_label.text = "%s UNLOCKED · EQUIPPED" % _theme_name(theme_id)

func _on_store_purchase_failed(message: String) -> void:
    theme_action_button.disabled = false
    restore_button.disabled = not store_connected
    if message.to_lower().contains("cancel"):
        theme_status_label.text = "PURCHASE CANCELLED"
    else:
        theme_status_label.text = "PURCHASE FAILED · %s" % message.to_upper()
    _refresh_theme_screen()

func _restore_purchases() -> void:
    if not store_connected:
        theme_status_label.text = "STORE IS NOT READY"
        return
    restore_button.disabled = true
    theme_action_button.disabled = true
    theme_status_label.text = "RESTORING PURCHASES..."
    iap_service.restore_theme_purchases()

func _on_store_restore_completed(theme_ids: Array[String]) -> void:
    for theme_id in theme_ids:
        if THEME_IDS.has(theme_id) and theme_id != "midnight" and not owned_themes.has(theme_id):
            owned_themes.append(theme_id)
    _save()
    restore_button.disabled = false
    _refresh_theme_screen()
    if theme_ids.is_empty():
        theme_status_label.text = "RESTORE COMPLETE · NO PREMIUM DESIGNS FOUND"
    else:
        theme_status_label.text = "RESTORED %d PREMIUM DESIGN%s" % [theme_ids.size(), "" if theme_ids.size() == 1 else "S"]

func _on_store_restore_failed(message: String) -> void:
    restore_button.disabled = not store_connected
    _refresh_theme_screen()
    theme_status_label.text = "RESTORE FAILED · %s" % message.to_upper()
