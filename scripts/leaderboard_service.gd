extends Node

signal leaderboard_loaded(mode: String, top: Array, me: Variant)
signal leaderboard_failed(message: String)
signal score_submitted(player: Dictionary)
signal score_submit_failed(message: String)
signal name_saved(player: Dictionary)
signal name_save_failed(message: String)

const FUNCTION_URL := "https://bqctetqraszsvknczjjr.supabase.co/functions/v1/ninenine-leaderboard"
# Supabase anon keys are publishable client credentials, not service-role secrets.
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxY3RldHFyYXN6c3ZrbmN6ampyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwOTg5MDgsImV4cCI6MjEwMjY3NDkwOH0.RPFwJoBMyHrtdjELO4b_sZK0dMfEF5RlXY-mt6wI-yc"

func load_leaderboard(mode: String, player_id: String, limit: int = 25) -> void:
    var safe_mode := "streak" if mode == "streak" else "hit"
    var safe_limit := clampi(limit, 1, 100)
    var url := "%s?mode=%s&limit=%d&player_id=%s" % [FUNCTION_URL, safe_mode, safe_limit, player_id.uri_encode()]
    _request(url, HTTPClient.METHOD_GET, "", func(code: int, payload: Variant) -> void:
        if code < 200 or code >= 300 or typeof(payload) != TYPE_DICTIONARY:
            leaderboard_failed.emit(_error_message(payload, "Leaderboard unavailable"))
            return
        var data: Dictionary = payload
        var top_value = data.get("top", [])
        var top: Array = top_value if typeof(top_value) == TYPE_ARRAY else []
        leaderboard_loaded.emit(safe_mode, top, data.get("me", null))
    )

func submit_score(player_id: String, score_milli: int, platform: String, app_version: String) -> void:
    var body := JSON.stringify({
        "action": "submit_score",
        "player_id": player_id,
        "score_milli": clampi(score_milli, 0, 100000),
        "platform": platform,
        "app_version": app_version,
    })
    _request(FUNCTION_URL, HTTPClient.METHOD_POST, body, func(code: int, payload: Variant) -> void:
        if code < 200 or code >= 300 or typeof(payload) != TYPE_DICTIONARY:
            score_submit_failed.emit(_error_message(payload, "Score sync failed"))
            return
        var data: Dictionary = payload
        var player_value = data.get("player", {})
        score_submitted.emit(player_value if typeof(player_value) == TYPE_DICTIONARY else {})
    )

func save_name(player_id: String, display_name: String) -> void:
    var body := JSON.stringify({
        "action": "set_name",
        "player_id": player_id,
        "display_name": display_name.strip_edges().to_upper(),
    })
    _request(FUNCTION_URL, HTTPClient.METHOD_POST, body, func(code: int, payload: Variant) -> void:
        if code < 200 or code >= 300 or typeof(payload) != TYPE_DICTIONARY:
            name_save_failed.emit(_error_message(payload, "Name could not be saved"))
            return
        var data: Dictionary = payload
        var player_value = data.get("player", {})
        name_saved.emit(player_value if typeof(player_value) == TYPE_DICTIONARY else {})
    )

func _request(url: String, method: HTTPClient.Method, body: String, callback: Callable) -> void:
    var request := HTTPRequest.new()
    request.timeout = 12.0
    add_child(request)
    request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
        var text := response_body.get_string_from_utf8()
        var parsed = JSON.parse_string(text) if not text.is_empty() else {}
        callback.call(response_code, parsed)
        request.queue_free()
    , CONNECT_ONE_SHOT)

    var headers := PackedStringArray([
        "Authorization: Bearer %s" % ANON_KEY,
        "apikey: %s" % ANON_KEY,
        "Content-Type: application/json",
    ])
    var error := request.request(url, headers, method, body)
    if error != OK:
        callback.call(0, {"error": "request_start_failed"})
        request.queue_free()

func _error_message(payload: Variant, fallback: String) -> String:
    if typeof(payload) == TYPE_DICTIONARY:
        var data: Dictionary = payload
        var value := str(data.get("error", ""))
        if not value.is_empty():
            return value.replace("_", " ").capitalize()
    return fallback
