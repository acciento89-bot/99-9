extends Node

const Types = preload("res://addons/godot-iap/types.gd")
const GodotIapWrapperScript = preload("res://addons/godot-iap/godot_iap.gd")
const IOS_GDEXTENSION_PATH := "res://addons/godot-iap/bin/godot_iap.gdextension"

signal store_state_changed(ready: bool, message: String)
signal products_updated(prices: Dictionary)
signal entitlements_updated(theme_ids: Array[String])
signal purchase_completed(theme_id: String)
signal purchase_failed(message: String)
signal restore_completed(theme_ids: Array[String])
signal restore_failed(message: String)
signal remove_ads_product_updated(price: String)
signal remove_ads_entitlement_updated(owned: bool)
signal remove_ads_purchase_completed

const PRODUCT_BY_THEME := {
    "neon": "de.kamilunavo.ninenine.theme.neon",
    "gold": "de.kamilunavo.ninenine.theme.gold",
    "aurora": "de.kamilunavo.ninenine.theme.aurora",
}
const REMOVE_ADS_PRODUCT := "de.kamilunavo.ninenine.removeads"

var iap: Node
var store_ready := false
var products: Dictionary = {}
var prices: Dictionary = {}
var remove_ads_price := ""
var _started := false
var _catalog_loaded := false

func start_store() -> void:
    if _started and store_ready:
        return
    _started = true

    if OS.get_name() not in ["iOS", "Android"]:
        store_state_changed.emit(false, "Store available on iOS / Android device")
        return

    if OS.get_name() == "iOS":
        _ensure_ios_native_extension()

    iap = get_node_or_null("/root/GodotIapPlugin")
    if iap == null:
        iap = GodotIapWrapperScript.new()
        iap.name = "GodotIapFallback"
        add_child(iap)
        if not iap.is_node_ready():
            await iap.ready
    elif not iap.is_node_ready():
        await iap.ready

    _connect_iap_signals()

    store_state_changed.emit(false, "Connecting to store...")
    var connected = await iap.init_connection()
    if not bool(connected) and OS.get_name() == "iOS":
        await get_tree().create_timer(0.35).timeout
        _ensure_ios_native_extension()
        connected = await iap.init_connection()

    store_ready = bool(connected)
    if not store_ready:
        _started = false
        store_state_changed.emit(false, "Store connection unavailable")
        return

    store_state_changed.emit(true, "Store connected · loading products")
    await _fetch_products()

    if prices.is_empty() and remove_ads_price.is_empty():
        store_state_changed.emit(true, "Store connected · products unavailable")
    else:
        store_state_changed.emit(true, "Store ready")

    await refresh_entitlements()

func _ensure_ios_native_extension() -> void:
    if OS.get_name() != "iOS" or ClassDB.class_exists("GodotIap"):
        return
    if not FileAccess.file_exists(IOS_GDEXTENSION_PATH):
        push_error("[99.9 IAP] Missing iOS GDExtension descriptor")
        return
    var load_result := GDExtensionManager.load_extension(IOS_GDEXTENSION_PATH)
    if load_result != OK and not ClassDB.class_exists("GodotIap"):
        push_error("[99.9 IAP] Could not load iOS StoreKit extension: %s" % load_result)

func _connect_iap_signals() -> void:
    if iap == null:
        return
    if not iap.purchase_updated.is_connected(_on_purchase_updated):
        iap.purchase_updated.connect(_on_purchase_updated)
    if not iap.purchase_error.is_connected(_on_purchase_error):
        iap.purchase_error.connect(_on_purchase_error)
    if not iap.products_fetched.is_connected(_on_products_fetched):
        iap.products_fetched.connect(_on_products_fetched)

func _fetch_products() -> void:
    if not store_ready or iap == null:
        return

    _catalog_loaded = false
    products.clear()
    prices.clear()
    remove_ads_price = ""

    var request = Types.ProductRequest.new()
    var sku_list: Array[String] = []
    for sku in PRODUCT_BY_THEME.values():
        sku_list.append(str(sku))
    sku_list.append(REMOVE_ADS_PRODUCT)
    request.skus = sku_list
    request.type = Types.ProductQueryType.IN_APP

    var fetched = await iap.fetch_products(request)
    if fetched is Array and not fetched.is_empty():
        _consume_products(fetched)
    else:
        _catalog_loaded = true
        products_updated.emit(prices.duplicate())
        remove_ads_product_updated.emit(remove_ads_price)

func _on_products_fetched(result: Dictionary) -> void:
    var fetched = result.get("products", [])
    if fetched is Array and not fetched.is_empty():
        _consume_products(fetched)
    elif not _catalog_loaded:
        _catalog_loaded = true
        products_updated.emit(prices.duplicate())
        remove_ads_product_updated.emit(remove_ads_price)

func _consume_products(fetched: Array) -> void:
    for product in fetched:
        var product_id := _field_string(product, ["id", "productId", "product_id"])
        if product_id.is_empty():
            continue
        products[product_id] = product
        var display_price := _field_string(product, ["display_price", "displayPrice", "localizedPrice"])
        if product_id == REMOVE_ADS_PRODUCT:
            if not display_price.is_empty():
                remove_ads_price = display_price
            continue
        var theme_id := theme_for_product(product_id)
        if not theme_id.is_empty() and not display_price.is_empty():
            prices[theme_id] = display_price

    _catalog_loaded = true
    products_updated.emit(prices.duplicate())
    remove_ads_product_updated.emit(remove_ads_price)

func purchase_theme(theme_id: String) -> void:
    if not PRODUCT_BY_THEME.has(theme_id):
        purchase_failed.emit("Unknown premium design")
        return
    _purchase_product(str(PRODUCT_BY_THEME[theme_id]))

func purchase_remove_ads() -> void:
    if OS.get_name() != "iOS":
        purchase_failed.emit("Remove Ads is available on iOS")
        return
    _purchase_product(REMOVE_ADS_PRODUCT)

func _purchase_product(product_id: String) -> void:
    if not store_ready or iap == null:
        purchase_failed.emit("Store is not ready yet")
        return

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
    var remove_ads_owned := false
    if not store_ready or iap == null:
        return owned
    var result = await iap.get_available_purchases_result()
    if not (result is Dictionary) or not bool(result.get("success", false)):
        return owned
    var purchases = result.get("purchases", [])
    if purchases is Array:
        for purchase in purchases:
            var product_id := _field_string(purchase, ["product_id", "productId", "id"])
            if product_id == REMOVE_ADS_PRODUCT:
                remove_ads_owned = true
                continue
            var theme_id := theme_for_product(product_id)
            if not theme_id.is_empty() and not owned.has(theme_id):
                owned.append(theme_id)
    entitlements_updated.emit(owned)
    remove_ads_entitlement_updated.emit(remove_ads_owned)
    return owned

func get_display_price(theme_id: String) -> String:
    return str(prices.get(theme_id, ""))

func get_remove_ads_price() -> String:
    return remove_ads_price

func theme_for_product(product_id: String) -> String:
    for theme_id in PRODUCT_BY_THEME.keys():
        if str(PRODUCT_BY_THEME[theme_id]) == product_id:
            return str(theme_id)
    return ""

func _on_purchase_updated(purchase: Dictionary) -> void:
    var product_id := _field_string(purchase, ["productId", "product_id", "id"])
    var state := _field_string(purchase, ["purchaseState", "purchase_state"])
    if not state.is_empty() and state.to_lower() not in ["purchased", "purchased_successfully"]:
        return

    if product_id == REMOVE_ADS_PRODUCT:
        var remove_finish = await iap.finish_transaction_dict(purchase, false)
        if not _result_success(remove_finish):
            push_warning("IAP transaction finish reported failure for %s" % product_id)
        remove_ads_purchase_completed.emit()
        remove_ads_entitlement_updated.emit(true)
        return

    var theme_id := theme_for_product(product_id)
    if theme_id.is_empty():
        return

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
