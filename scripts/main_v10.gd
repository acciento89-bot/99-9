extends "res://scripts/main_v9.gd"

# Final iOS release pass: production AdMob + non-consumable Remove Ads.

var remove_ads_owned := false
var remove_ads_price := ""
var remove_ads_button: Button
var remove_ads_status_label: Label

func _ready() -> void:
    iap_service.remove_ads_product_updated.connect(_on_remove_ads_product_updated)
    iap_service.remove_ads_entitlement_updated.connect(_on_remove_ads_entitlement_updated)
    iap_service.remove_ads_purchase_completed.connect(_on_remove_ads_purchase_completed)
    super._ready()
    ads_service.set_ads_removed(remove_ads_owned)
    _refresh_remove_ads_ui()

func _build_settings_ui() -> void:
    super._build_settings_ui()

    var panel := _make_panel("card")
    _place(panel, Vector2(130, 1475), Vector2(820, 270), settings_layer)

    var title := _make_label("REMOVE ADS", 31, HORIZONTAL_ALIGNMENT_LEFT)
    _place(title, Vector2(45, 24), Vector2(340, 52), panel)

    var desc := _make_muted_label("One-time purchase. Removes interstitial ads permanently.", 19, HORIZONTAL_ALIGNMENT_LEFT)
    _place(desc, Vector2(45, 72), Vector2(720, 56), panel)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    remove_ads_button = _make_button("LOADING STORE...", Vector2(360, 78), 22, "accent")
    _place(remove_ads_button, Vector2(410, 145), Vector2(360, 78), panel)
    remove_ads_button.disabled = true
    remove_ads_button.pressed.connect(_purchase_remove_ads)

    remove_ads_status_label = _make_muted_label("Checking App Store ownership...", 18, HORIZONTAL_ALIGNMENT_LEFT)
    _place(remove_ads_status_label, Vector2(45, 148), Vector2(335, 78), panel)
    remove_ads_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _purchase_remove_ads() -> void:
    if remove_ads_owned:
        return
    if not store_connected:
        remove_ads_status_label.text = "APP STORE NOT READY"
        return
    remove_ads_button.disabled = true
    remove_ads_button.text = "OPENING STORE..."
    remove_ads_status_label.text = "CONFIRM ONE-TIME PURCHASE"
    iap_service.purchase_remove_ads()

func _on_remove_ads_product_updated(price: String) -> void:
    remove_ads_price = price
    _refresh_remove_ads_ui()

func _on_remove_ads_entitlement_updated(owned: bool) -> void:
    remove_ads_owned = owned
    ads_service.set_ads_removed(owned)
    _save()
    _refresh_remove_ads_ui()

func _on_remove_ads_purchase_completed() -> void:
    remove_ads_owned = true
    ads_service.set_ads_removed(true)
    _save()
    _refresh_remove_ads_ui()

func _on_store_state_changed(ready: bool, message: String) -> void:
    super._on_store_state_changed(ready, message)
    _refresh_remove_ads_ui()

func _on_store_purchase_failed(message: String) -> void:
    super._on_store_purchase_failed(message)
    if remove_ads_status_label != null:
        remove_ads_status_label.text = "PURCHASE CANCELLED" if message.to_lower().contains("cancel") else "PURCHASE FAILED"
    _refresh_remove_ads_ui()

func _refresh_remove_ads_ui() -> void:
    if remove_ads_button == null or remove_ads_status_label == null:
        return
    if remove_ads_owned:
        remove_ads_button.text = "ADS REMOVED"
        remove_ads_button.disabled = true
        remove_ads_status_label.text = "OWNED · RESTORES WITH YOUR APPLE ID"
        return
    if not store_connected:
        remove_ads_button.text = "CONNECTING..."
        remove_ads_button.disabled = true
        remove_ads_status_label.text = "CONNECTING TO APP STORE"
        return
    if remove_ads_price.is_empty():
        remove_ads_button.text = "NOT AVAILABLE YET"
        remove_ads_button.disabled = true
        remove_ads_status_label.text = "APP STORE ITEM IS STILL PROCESSING"
        return
    remove_ads_button.text = "REMOVE ADS · %s" % remove_ads_price
    remove_ads_button.disabled = false
    remove_ads_status_label.text = "ONE-TIME PURCHASE"

func _load_save() -> void:
    super._load_save()
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) == TYPE_DICTIONARY:
        remove_ads_owned = bool(parsed.get("remove_ads_owned", false))

func _save() -> void:
    super._save()
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var read_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if read_file == null:
        return
    var parsed = JSON.parse_string(read_file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        parsed = {}
    parsed["remove_ads_owned"] = remove_ads_owned
    var write_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if write_file != null:
        write_file.store_string(JSON.stringify(parsed))