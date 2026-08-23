extends "res://scripts/leaderboard_service.gd"

# iOS termination-safe network layer. No anonymous GDScript Callables are kept
# alive by HTTPRequest signals while the application is being terminated.

const ACTION_LOAD := "load"
const ACTION_SUBMIT := "submit"
const ACTION_NAME := "name"

func load_leaderboard(mode: String, player_id: String, limit: int = 25) -> void:
    var safe_mode := "streak" if mode == "streak" else "hit"
    var safe_limit := clampi(limit, 1, 100)
    var url := "%s?mode=%s&limit=%d&player_id=%s" % [FUNCTION_URL, safe_mode, safe_limit, player_id.uri_encode()]
    _request_ios_safe(url, HTTPClient.METHOD_GET, "", ACTION_LOAD, safe_mode)

func submit_score(player_id: String, score_milli: int, platform: String, app_version: String) -> void:
    var body := JSON.stringify({
        "action": "submit_score",
        "player_id": player_id,
        "score_milli": clampi(score_milli, 0, 100000),
        "platform": platform,
        "app_version": app_version,
    })
    _request_ios_safe(FUNCTION_URL, HTTPClient.METHOD_POST, body, ACTION_SUBMIT, "")

func save_name(player_id: String, display_name: String) -> void:
    var body := JSON.stringify({
        "action": "set_name",
        "player_id": player_id,
        "display_name": display_name.strip_edges().to_upper(),
    })
    _request_ios_safe(FUNCTION_URL, HTTPClient.METHOD_POST, body, ACTION_NAME, "")

func _request_ios_safe(url: String, method: HTTPClient.Method, body: String, action: String, context: String) -> void:
    var request := HTTPRequest.new()
    request.timeout = 12.0
    add_child(request)
    var callback := Callable(self, "_on_ios_request_completed").bind(request, action, context)
    request.request_completed.connect(callback, CONNECT_ONE_SHOT)

    var headers := PackedStringArray([
        "Authorization: Bearer %s" % ANON_KEY,
        "apikey: %s" % ANON_KEY,
        "Content-Type: application/json",
    ])
    var error := request.request(url, headers, method, body)
    if error != OK:
        _emit_ios_request_failure(action, {"error": "request_start_failed"})
        request.queue_free()

func _on_ios_request_completed(
    _result: int,
    response_code: int,
    _headers: PackedStringArray,
    response_body: PackedByteArray,
    request: HTTPRequest,
    action: String,
    context: String
) -> void:
    var text := response_body.get_string_from_utf8()
    var parsed = JSON.parse_string(text) if not text.is_empty() else {}
    var payload: Variant = parsed if parsed != null else {}

    if response_code < 200 or response_code >= 300 or typeof(payload) != TYPE_DICTIONARY:
        _emit_ios_request_failure(action, payload)
        if is_instance_valid(request):
            request.queue_free()
        return

    var data: Dictionary = payload
    match action:
        ACTION_LOAD:
            var top_value = data.get("top", [])
            var top: Array = top_value if typeof(top_value) == TYPE_ARRAY else []
            leaderboard_loaded.emit(context, top, data.get("me", null))
        ACTION_SUBMIT:
            var player_value = data.get("player", {})
            score_submitted.emit(player_value if typeof(player_value) == TYPE_DICTIONARY else {})
        ACTION_NAME:
            var player_value = data.get("player", {})
            name_saved.emit(player_value if typeof(player_value) == TYPE_DICTIONARY else {})

    if is_instance_valid(request):
        request.queue_free()

func _emit_ios_request_failure(action: String, payload: Variant) -> void:
    match action:
        ACTION_LOAD:
            leaderboard_failed.emit(_error_message(payload, "Leaderboard unavailable"))
        ACTION_SUBMIT:
            score_submit_failed.emit(_error_message(payload, "Score sync failed"))
        ACTION_NAME:
            name_save_failed.emit(_error_message(payload, "Name could not be saved"))

func _exit_tree() -> void:
    for child in get_children():
        if child is HTTPRequest:
            child.cancel_request()
