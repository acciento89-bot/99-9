extends "res://addons/godot-iap/godot_iap.gd"

# Build-12 crash log ends in GDScriptLambdaSelfCallable destruction during
# GDScriptLanguage::finish(). The stock wrapper creates a self-capturing timeout
# lambda for every iOS async StoreKit request. This override keeps the same
# request/token logic but uses a bound named Callable instead.

const BaseGodotIap = preload("res://addons/godot-iap/godot_iap.gd")

func _await_products_fetched_for(
    method: String,
    request_id: String,
    timeout_seconds: float = -1.0
) -> Dictionary:
    var cache_key := _ios_async_result_key(method, request_id)
    if _ios_async_results.has(cache_key):
        var cached = _take_cached_ios_async_result(cache_key)
        _mark_ios_async_terminal(cache_key)
        return cached
    if _ios_async_terminal_keys.has(cache_key):
        return {
            "success": false,
            "code": "service-error",
            "error": "%s completion is no longer available" % method,
            "method": method,
            "requestId": request_id,
        }

    var waiter = BaseGodotIap.IosAsyncWaiter.new()
    _ios_async_waiters[cache_key] = waiter

    if _ios_async_results.has(cache_key):
        var cached = _take_cached_ios_async_result(cache_key)
        _ios_async_waiters.erase(cache_key)
        _mark_ios_async_terminal(cache_key)
        return cached

    var effective_timeout := timeout_seconds
    if effective_timeout <= 0.0:
        effective_timeout = _ios_async_timeout_seconds

    var tree := get_tree()
    if tree == null:
        _ios_async_waiters.erase(cache_key)
        _mark_ios_async_terminal(cache_key)
        return {
            "success": false,
            "code": "not-prepared",
            "error": "%s cannot await a completion outside the scene tree" % method,
            "method": method,
            "requestId": request_id,
        }

    var timer := tree.create_timer(effective_timeout)
    var timeout_payload := {
        "success": false,
        "code": "service-timeout",
        "error": "%s timed out after %.1f seconds" % [method, effective_timeout],
        "method": method,
        "requestId": request_id,
    }
    var timeout_callback := Callable(self, "_complete_ios_async_waiter").bind(cache_key, timeout_payload)
    waiter.arm_timeout(timer, timeout_callback)

    var payload = await waiter.completed
    _ios_async_waiters.erase(cache_key)
    _mark_ios_async_terminal(cache_key)
    if payload is Dictionary:
        return payload
    return {
        "success": false,
        "code": "service-error",
        "error": "%s returned an invalid completion" % method,
    }
