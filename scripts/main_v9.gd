extends "res://scripts/main_v8.gd"

# Native iOS sharing + upgrade-safe statistics migration.

func _load_save() -> void:
    super._load_save()

    # Build 8 and older saves did not track these counters. Preserve truthful
    # minimums that can be inferred from already persisted personal records.
    hits_99_plus = maxi(hits_99_plus, local_perfect_count)
    hits_999_plus = maxi(hits_999_plus, local_perfect_count)
    if best_value >= 99.000:
        hits_99_plus = maxi(hits_99_plus, 1)
    if best_value >= STREAK_THRESHOLD:
        hits_999_plus = maxi(hits_999_plus, 1)

    # Ignore unknown/corrupt achievement IDs so the progress count can never
    # exceed the actual catalog size after an upgrade.
    var valid_ids: Array[String] = []
    for definition in _achievement_definitions():
        valid_ids.append(str(definition["id"]))
    for index in range(unlocked_achievements.size() - 1, -1, -1):
        if not valid_ids.has(unlocked_achievements[index]):
            unlocked_achievements.remove_at(index)


func _refresh_stats_screen() -> void:
    super._refresh_stats_screen()
    if stats_average_value_label != null and games_played > 0 and tracked_rounds == 0:
        stats_average_value_label.text = "NEW"
    if stats_share_status_label != null and games_played > 0 and tracked_rounds == 0:
        stats_share_status_label.text = "AVG TRACKING STARTS WITH THIS UPDATE · OLD RECORDS STAY INTACT"


func _share_result_value(value: float, streak_value: int) -> void:
    var message := "I hit %s in 99.9%% — can you get closer?" % _format_percent(value)
    if streak_value > 1:
        message += " My streak: %d." % streak_value

    var image_path := await _create_share_card(value, streak_value)
    var shared := false

    # Native iOS UIActivityViewController via kyoz/godot-share.
    if Engine.has_singleton("Share"):
        var native_share = Engine.get_singleton("Share")
        if native_share != null:
            if native_share.has_method("shareImage") and not image_path.is_empty():
                native_share.call("shareImage", image_path, "99.9%", "My 99.9% result", message)
                shared = true
            elif native_share.has_method("shareText"):
                native_share.call("shareText", "99.9%", "My 99.9% result", message)
                shared = true
            elif native_share.has_method("share_image") and not image_path.is_empty():
                native_share.call("share_image", image_path, "99.9%", "My 99.9% result", message)
                shared = true
            elif native_share.has_method("share_text"):
                native_share.call("share_text", "99.9%", "My 99.9% result", message)
                shared = true

    if shared:
        if stats_share_status_label != null:
            stats_share_status_label.text = "SHARE SHEET OPENED"
        return

    DisplayServer.clipboard_set(message)
    if OS.get_name() == "iOS":
        OS.shell_open("sms:&body=" + message.uri_encode())
    if stats_share_status_label != null:
        stats_share_status_label.text = "RESULT COPIED · READY TO SHARE"
