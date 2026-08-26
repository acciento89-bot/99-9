extends "res://scripts/main_v11_ios_shutdown_safe.gd"

# Build 17 App Review remediation:
# - make Restore Purchases unmistakably visible in Settings
# - remove third-party platform wording from all customer-facing iOS labels
# - preserve the Build 16 shutdown-safe StoreKit/AdMob paths

var review_restore_button: Button
var review_restore_status_label: Label


func _ready() -> void:
    super._ready()
    if OS.get_name() == "iOS":
        _neutralize_third_party_platform_copy()


func _build_settings_ui() -> void:
    super._build_settings_ui()

    var purchases_panel := _make_panel("soft")
    _place(purchases_panel, Vector2(130, 930), Vector2(820, 220), settings_layer)

    var purchases_title := _make_label("PURCHASES", 31, HORIZONTAL_ALIGNMENT_LEFT)
    _place(purchases_title, Vector2(45, 24), Vector2(300, 50), purchases_panel)

    var purchases_desc := _make_muted_label("Re-check your App Store purchases and restore permanent unlocks.", 18, HORIZONTAL_ALIGNMENT_LEFT)
    _place(purchases_desc, Vector2(45, 70), Vector2(720, 44), purchases_panel)
    purchases_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    review_restore_button = _make_button("RESTORE PURCHASES", Vector2(330, 72), 21, "secondary")
    _place(review_restore_button, Vector2(435, 124), Vector2(330, 72), purchases_panel)
    review_restore_button.disabled = true
    review_restore_button.pressed.connect(Callable(self, "_review_restore_purchases"))

    review_restore_status_label = _make_muted_label("CONNECTING TO APP STORE", 17, HORIZONTAL_ALIGNMENT_LEFT)
    _place(review_restore_status_label, Vector2(45, 132), Vector2(360, 58), purchases_panel)
    review_restore_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _review_restore_purchases() -> void:
    if not store_connected:
        review_restore_status_label.text = "APP STORE NOT READY"
        return

    review_restore_button.disabled = true
    review_restore_status_label.text = "RESTORING PURCHASES..."
    iap_service.restore_theme_purchases()


func _on_store_state_changed(ready: bool, message: String) -> void:
    super._on_store_state_changed(ready, message)
    if review_restore_button == null or review_restore_status_label == null:
        return
    review_restore_button.disabled = not ready
    if ready:
        review_restore_status_label.text = "READY TO RESTORE"
    else:
        review_restore_status_label.text = message.to_upper()


func _on_store_restore_completed(theme_ids: Array[String]) -> void:
    super._on_store_restore_completed(theme_ids)
    if review_restore_button != null:
        review_restore_button.disabled = not store_connected
    if review_restore_status_label != null:
        review_restore_status_label.text = "RESTORE COMPLETE · PURCHASES REFRESHED"


func _on_store_restore_failed(message: String) -> void:
    super._on_store_restore_failed(message)
    if review_restore_button != null:
        review_restore_button.disabled = not store_connected
    if review_restore_status_label != null:
        review_restore_status_label.text = "RESTORE FAILED · %s" % message.to_upper()


func _neutralize_third_party_platform_copy() -> void:
    for node in find_children("*", "Label", true, false):
        if not (node is Label):
            continue
        var text_value: String = str(node.text)
        text_value = text_value.replace("iOS + ANDROID", "ALL PLAYERS")
        text_value = text_value.replace("iOS + Android", "ALL PLAYERS")
        node.text = text_value
