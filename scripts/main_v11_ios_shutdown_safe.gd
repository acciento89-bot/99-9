extends "res://scripts/main_v10.gd"

# iOS-only release hardening for the termination crash seen in Build 12.
# The crash log ends in GDScriptLambdaSelfCallable destruction while Godot is
# shutting the GDScript language down. Older UI builders leave anonymous
# lambdas connected to long-lived controls. Replace those connections with
# ordinary named Callables once the inherited UI has been built.

func _ready() -> void:
    super._ready()
    if OS.get_name() == "iOS":
        _replace_ios_lambda_connections()

func _notification(what: int) -> void:
    if OS.get_name() != "iOS":
        return
    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT or what == MainLoop.NOTIFICATION_APPLICATION_PAUSED:
        _save()

func _replace_ios_lambda_connections() -> void:
    _replace_button_connection(menu_layer, "WORLD RANKING", "_ios_open_hit_ranking")
    _replace_button_connection(menu_layer, "MY STATS", "_ios_open_stats")

    _replace_button_connection(leaderboard_layer, "BACK", "_ios_go_menu")
    _replace_button_connection(leaderboard_layer, "BEST HIT", "_ios_open_hit_ranking")
    _replace_button_connection(leaderboard_layer, "LONGEST STREAK", "_ios_open_streak_ranking")
    _replace_button_connection(leaderboard_layer, "REFRESH", "_ios_refresh_ranking")

    _replace_button_connection(settings_layer, "PRIVACY OPTIONS", "_ios_open_privacy_options")
    _replace_button_connection(stats_layer, "BACK", "_ios_go_menu")
    _replace_button_connection(stats_layer, "OPEN WORLD RANKING", "_ios_open_hit_ranking")

    if name_input != null:
        _disconnect_signal_connections(name_input.text_submitted)
        name_input.text_submitted.connect(Callable(self, "_ios_name_submitted"))

func _replace_button_connection(root: Node, text_value: String, method_name: StringName) -> void:
    if root == null:
        return
    for child in root.find_children("*", "Button", true, false):
        if child is Button and child.text == text_value:
            _disconnect_signal_connections(child.pressed)
            child.pressed.connect(Callable(self, method_name))

func _disconnect_signal_connections(signal_value: Signal) -> void:
    for connection in signal_value.get_connections():
        var callback: Callable = connection.get("callable", Callable())
        if callback.is_valid() and signal_value.is_connected(callback):
            signal_value.disconnect(callback)

func _ios_open_hit_ranking() -> void:
    _open_leaderboard("hit")

func _ios_open_streak_ranking() -> void:
    _open_leaderboard("streak")

func _ios_refresh_ranking() -> void:
    _open_leaderboard(leaderboard_mode)

func _ios_open_stats() -> void:
    _refresh_stats_screen()
    _show_screen(AppScreen.STATS)

func _ios_go_menu() -> void:
    _show_screen(AppScreen.MENU)

func _ios_open_privacy_options() -> void:
    ads_service.show_privacy_options()

func _ios_name_submitted(_submitted: String) -> void:
    _save_player_name()
