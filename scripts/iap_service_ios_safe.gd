extends "res://scripts/iap_service.gd"

const SafeGodotIapWrapperScript = preload("res://addons/godot-iap/godot_iap_ios_safe.gd")

var _ios_suspended := false
var _ios_terminating := false

func start_store() -> void:
    if OS.get_name() != "iOS":
        super.start_store()
        return
    if _started or _ios_suspended or _ios_terminating:
        return
    _started = true

    if iap == null or not is_instance_valid(iap):
        iap = SafeGodotIapWrapperScript.new()
        iap.name = "GodotIapIOSSafe"
        add_child(iap)
        if not iap.is_node_ready():
            await iap.ready
    elif not iap.is_node_ready():
        await iap.ready

    if _ios_suspended or _ios_terminating or not is_inside_tree():
        return

    _connect_iap_signals()
    store_state_changed.emit(false, "Connecting to store...")

    var connected = await iap.init_connection()
    if _ios_suspended or _ios_terminating or not is_inside_tree():
        return

    store_ready = bool(connected)
    if not store_ready:
        store_state_changed.emit(false, "Store connection unavailable")
        return

    store_state_changed.emit(true, "Store connected · loading products")
    await _fetch_products()
    if _ios_suspended or _ios_terminating or not is_inside_tree():
        return

    if prices.is_empty() and remove_ads_price.is_empty():
        store_state_changed.emit(true, "Store connected · products unavailable")
    else:
        store_state_changed.emit(true, "Store ready")

    await refresh_entitlements()

func _notification(what: int) -> void:
    if OS.get_name() != "iOS":
        return

    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT or what == MainLoop.NOTIFICATION_APPLICATION_PAUSED:
        _ios_suspended = true
        _cancel_ios_pending("application-paused", "The app paused before the StoreKit request completed")
        return

    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN or what == MainLoop.NOTIFICATION_APPLICATION_RESUMED:
        if _ios_terminating:
            return
        var should_restart := _ios_suspended and not store_ready
        _ios_suspended = false
        if should_restart:
            _started = false
            call_deferred("start_store")

func _cancel_ios_pending(code: String, message: String) -> void:
    if iap == null or not is_instance_valid(iap):
        return
    if iap.has_method("_cancel_pending_ios_async"):
        iap.call("_cancel_pending_ios_async", code, message)

func _exit_tree() -> void:
    if OS.get_name() != "iOS":
        return
    _ios_terminating = true
    _ios_suspended = true
    store_ready = false
    _cancel_ios_pending("service-disconnected", "The app is terminating before the StoreKit request completed")
