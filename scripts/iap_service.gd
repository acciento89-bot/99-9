extends Node

const Types = preload("res://addons/godot-iap/types.gd")
const GodotIapWrapperScript = preload("res://addons/godot-iap/godot_iap.gd")

signal store_state_changed(ready: bool, message: String)
signal products_updated(prices: Dictionary)
signal entitlements_updated(theme_ids: Array[String])
signal purchase_completed(theme_id: String)
signal purchase_failed(message: String)
signal restore_completed(theme_ids: Array[String])
signal restore_failed(message: String)

const PRODUCT_BY_THEME := {
    "neon": "de.kamilunavo.ninenine.theme.neon",
    "gold": "de.kamilunavo.ninenine.theme.gold",
    "aurora": "de.kamilunavo.ninenine.theme.aurora",
}

var iap: Node
var store_ready := false
var products: Dictionary = {}
var prices: Dictionary = {}
var _started := false

func start_store() -> void:
    if _started:
        return
    _started = true

    if OS.get_name() not in ["iOS", "Android"]:
        store_state_changed.emit(false, "Store available on iOS / Android device")
        return

    iap = GodotIapWrapperScript.new()
    iap.name = "GodotIapWrapper"
    add_child(iap)
    iap.purchase_updated.connect(_on_purchase_updated)
    iap.purchase_error.connect(_on_purchase_error)
    iap.products_fetched.connect(_on_products_fetched)

    store_state_changed.emit(false, "Connecting to store...")
    var connected = await iap.init_connection()
    store_ready = bool(connected)
    if not store_ready:
        store_state_changed.emit(false, "Store connection unavailable")
        return

    store_state_changed.emit(true, "Store connected")
    await _fetch_products()
    await refresh_entitlements()

func _fetch_products() -> void:
    if not store_ready or iap == null:
        return
    var request = Types.ProductRequest.new()
    var sku_list: Array[String] = []
    for sku in PRODUCT_BY_THEME.values():
        sku_list.append(str(sku))
    request.skus = sku_list
    request.type = Types.ProductQueryType.IN_APP
    var fetched = await iap.fetch_products(request)
    if fetched is Array and not fetched.is_empty():
        _consume_products(fetched)

func _on_products_fetched(result: Dictionary) -> void:
    var fetched = result.get("products", [])
    if fetched is Array and not fetched.is_empty():
        _consume_products(fetched)

func _consume_products(fetched: Array) -> void:
    for product in fetched:
        var product_id := _field_string(product, ["id", "productId", "product_id"])
        if product_id.is_empty():
            continue
        products[product_id] = product
        var theme_id := theme_for_product(product_id)
        if theme_id.is_empty():
            continue
        var display_price := _field_string(product, ["display_price", "displayPrice", "localizedPrice"])
        if not display_price.is_empty():
            prices[theme_id] = display_price
    products_updated.emit(prices.duplicate())

func purchase_theme(theme_id: String) -> void:
    if not PRODUCT_BY_THEME.has(theme_id):
        purchase_failed.emit("Unknown premium design")
        return
    if not store_ready or iap == null:
        purchase_failed.emit("Store is not ready yet")
        return

    var product_id := str(PRODUCT_BY_THEME[theme_id])
    var props = Types.RequestPurchaseProps.new()
    props.request = Types.RequestPurchasePropsByPlatforms.new()
    props.request.apple = Types.RequestPurchaseIosProps.new()
    props.request.apple.sku = product_id
    props.request.google = Types.RequestPurchaseAndroidProps.new()
    var google_skus: Array[String] = [product_id]
    props.request.google.skus = google_skus
    props.type = Types.ProductQueryType.IN_APP
    iap.request_purchase(props)

func restore_theme_purchases() -> void:
    if not store_ready or iap == null:
        restore_failed.emit("Store is not ready yet")
        return
    var result = await iap.restore_purchases()
    if not _result_success(result):
        restore_failed.emit(_result_error(result, "Restore failed"))
        return
    var owned := await refresh_entitlements()
    restore_completed.emit(owned)

func refresh_entitlements() -> Array[String]:
    var owned: Array[String] = []
    if not store_ready or iap == null:
        return owned
    var result = await iap.get_available_purchases_result()
    if not (result is Dictionary) or not bool(result.get("success", false)):
        return owned
    var purchases = result.get("purchases", [])
    if purchases is Array:
        for purchase in purchases:
            var product_id := _field_string(purchase, ["product_id", "productId", "id"])
            var theme_id := theme_for_product(product_id)
            if not theme_id.is_empty() and not owned.has(theme_id):
                owned.append(theme_id)
    entitlements_updated.emit(owned)
    return owned

func get_display_price(theme_id: String) -> String:
    return str(prices.get(theme_id, ""))

func theme_for_product(product_id: String) -> String:
    for theme_id in PRODUCT_BY_THEME.keys():
        if str(PRODUCT_BY_THEME[theme_id]) == product_id:
            return str(theme_id)
    return ""

func _on_purchase_updated(purchase: Dictionary) -> void:
    var product_id := _field_string(purchase, ["productId", "product_id", "id"])
    var theme_id := theme_for_product(product_id)
    if theme_id.is_empty():
        return
    var state := _field_string(purchase, ["purchaseState", "purchase_state"])
    if not state.is_empty() and state.to_lower() not in ["purchased", "purchased_successfully"]:
        return

    # These designs are non-consumable. StoreKit / Play remains the source of truth;
    # local ownership is only a cache rebuilt through refresh/restore.
    var finish_result = await iap.finish_transaction_dict(purchase, false)
    if not _result_success(finish_result):
        push_warning("IAP transaction finish reported failure for %s" % product_id)
    purchase_completed.emit(theme_id)

func _on_purchase_error(error: Dictionary) -> void:
    var code := str(error.get("code", ""))
    var message := str(error.get("message", "Purchase failed"))
    if code.to_lower() in ["user-cancelled", "user_cancelled", "user-canceled", "user_canceled", "user_canceled_error"]:
        purchase_failed.emit("Purchase cancelled")
    else:
        purchase_failed.emit(message)

func _field_string(source: Variant, keys: Array) -> String:
    if source is Dictionary:
        for key in keys:
            if source.has(key) and source[key] != null:
                return str(source[key])
    elif typeof(source) == TYPE_OBJECT and source != null:
        for key in keys:
            var value = source.get(key)
            if value != null:
                return str(value)
    return ""

func _result_success(result: Variant) -> bool:
    if result is Dictionary:
        return bool(result.get("success", false))
    if typeof(result) == TYPE_OBJECT and result != null:
        var value = result.get("success")
        return bool(value) if value != null else false
    return false

func _result_error(result: Variant, fallback: String) -> String:
    if result is Dictionary:
        return str(result.get("error", fallback))
    if typeof(result) == TYPE_OBJECT and result != null:
        var value = result.get("error")
        if value != null and not str(value).is_empty():
            return str(value)
    return fallback
