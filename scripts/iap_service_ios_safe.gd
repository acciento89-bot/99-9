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

    # Reuse the editor-plugin autoload. Creating a second wrapper can leave the
    # duplicate without its native StoreKit bridge because initialization is
    # guarded globally inside GodotIap.
    if iap == null or not is_instance_valid(iap):
        var autoload_iap := get_node_or_null("/root/GodotIapPlugin")
        if autoload_iap != null and is_instance_valid(autoload_iap):
            iap = autoload_iap
        else:
            iap = SafeGodotIapWrapperScript.new()
            iap.name = "GodotIapIOSSafeFallback"
            add_child(iap)

    if iap != null and not iap.is_node_ready():
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
        _started = false
        store_state_changed.emit(false, "Store connection unavailable · reopen Designs to retry")
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

# Build 18 StoreKit fix:
# Keep the three premium designs in their own StoreKit request, matching the
# catalog shape that already worked on physical iPhone. Remove Ads is fetched
# separately so an unavailable/processing auxiliary SKU can never blank the
# entire premium design catalog.
func _fetch_products() -> void:
    if not store_ready or iap == null:
        return

    _catalog_loaded = false
    products.clear()
    prices.clear()
    remove_ads_price = ""

    var theme_request = Types.ProductRequest.new()
    var theme_skus: Array[String] = []
    for sku in PRODUCT_BY_THEME.values():
        theme_skus.append(str(sku))
    theme_request.skus = theme_skus
    theme_request.type = Types.ProductQueryType.IN_APP

    var theme_fetched = await iap.fetch_products(theme_request)
    if (not (theme_fetched is Array)) or theme_fetched.is_empty():
        # One short retry covers the occasional TestFlight StoreKit catalogue
        # race without turning an initial empty response into a permanent UI
        # state for this app session.
        await get_tree().create_timer(0.6).timeout
        if _ios_suspended or _ios_terminating or not is_inside_tree():
            return
        theme_fetched = await iap.fetch_products(theme_request)

    if theme_fetched is Array and not theme_fetched.is_empty():
        _consume_products(theme_fetched)
    else:
        _catalog_loaded = true
        products_updated.emit(prices.duplicate())

    if _ios_suspended or _ios_terminating or not is_inside_tree():
        return

    var remove_request = Types.ProductRequest.new()
    var remove_skus: Array[String] = [REMOVE_ADS_PRODUCT]
    remove_request.skus = remove_skus
    remove_request.type = Types.ProductQueryType.IN_APP

    var remove_fetched = await iap.fetch_products(remove_request)
    if remove_fetched is Array and not remove_fetched.is_empty():
        _consume_products(remove_fetched)
    else:
        remove_ads_product_updated.emit(remove_ads_price)

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
