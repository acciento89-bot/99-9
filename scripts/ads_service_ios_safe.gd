extends "res://scripts/ads_service.gd"

# iOS release-safe AdMob/UMP bridge.
# Build 17 additionally gates every iOS advertising path behind Apple's
# AppTrackingTransparency authorization before Mobile Ads can initialize.
# The app remains fully usable when tracking permission is denied.

const ATT_NOT_DETERMINED := 0
const ATT_RESTRICTED := 1
const ATT_DENIED := 2
const ATT_AUTHORIZED := 3

var _att = null
var _att_request_in_flight := false


func start_ads() -> void:
    if OS.get_name() != "iOS":
        super.start_ads()
        return
    if _started or _shutting_down:
        return

    if _ads_removed:
        _started = true
        ads_state_changed.emit(false, "ADS REMOVED")
        return

    if not Engine.has_singleton("GodotxATT"):
        _started = true
        _disable_ads_for_privacy("ADS DISABLED · TRACKING PERMISSION UNAVAILABLE")
        return

    _att = Engine.get_singleton("GodotxATT")
    if _att == null or not _att.has_method("get_status") or not _att.has_method("request_permission"):
        _started = true
        _disable_ads_for_privacy("ADS DISABLED · TRACKING PERMISSION UNAVAILABLE")
        return

    var status := int(_att.call("get_status"))
    if status == ATT_NOT_DETERMINED:
        if _att_request_in_flight:
            return
        var permission_callback := Callable(self, "_on_att_permission_result")
        if not _att.permission_result.is_connected(permission_callback):
            _att.permission_result.connect(permission_callback)
        _att_request_in_flight = true
        ads_state_changed.emit(false, "WAITING FOR TRACKING PERMISSION")
        _att.call("request_permission")
        return

    _continue_after_att(status)


func _on_att_permission_result(data: Dictionary) -> void:
    if _shutting_down:
        return
    _att_request_in_flight = false
    var status := int(data.get("status", ATT_DENIED))
    _continue_after_att(status)


func _continue_after_att(status: int) -> void:
    if _shutting_down or _ads_removed:
        return
    if status != ATT_AUTHORIZED:
        _started = true
        _disable_ads_for_privacy("ADS DISABLED · TRACKING PERMISSION NOT GRANTED")
        return

    # ATT has been resolved first. UMP consent and Mobile Ads initialization
    # continue through the existing release-safe path only after authorization.
    super.start_ads()


func _att_allows_tracking() -> bool:
    if OS.get_name() != "iOS":
        return true
    if _att == null:
        if not Engine.has_singleton("GodotxATT"):
            return false
        _att = Engine.get_singleton("GodotxATT")
    if _att == null or not _att.has_method("get_status"):
        return false
    return int(_att.call("get_status")) == ATT_AUTHORIZED


func show_privacy_options() -> void:
    if OS.get_name() != "iOS":
        super.show_privacy_options()
        return
    if _shutting_down or _ads_removed:
        return
    UserMessagingPlatform.show_privacy_options_form(Callable(self, "_on_privacy_options_result"))


func _on_privacy_options_result(error) -> void:
    if _shutting_down:
        return
    if error != null:
        ad_error.emit("PRIVACY OPTIONS · %s" % str(error.message))
    privacy_options_changed.emit(is_privacy_options_required())
    if _att_allows_tracking() and _consent_allows_ads():
        if not _ads_ready:
            _initialize_mobile_ads()
    else:
        _disable_ads_for_privacy("ADS DISABLED · CONSENT OR TRACKING PERMISSION REQUIRED")


func show_interstitial_if_ready() -> bool:
    if OS.get_name() != "iOS":
        return super.show_interstitial_if_ready()
    if not _att_allows_tracking():
        _disable_ads_for_privacy("ADS DISABLED · TRACKING PERMISSION NOT GRANTED")
        return false
    return super.show_interstitial_if_ready()


func _request_user_consent() -> void:
    if OS.get_name() != "iOS":
        super._request_user_consent()
        return
    if _shutting_down or _ads_removed or not _att_allows_tracking():
        return
    var params := ConsentRequestParameters.new()
    _consent_information.update(
        params,
        Callable(self, "_on_consent_info_updated_success"),
        Callable(self, "_on_consent_info_updated_failure")
    )


func _on_consent_info_updated_success() -> void:
    if _shutting_down:
        return
    privacy_options_changed.emit(is_privacy_options_required())
    if _consent_allows_ads():
        _initialize_mobile_ads()
    elif _consent_information != null and _consent_information.get_is_consent_form_available():
        _load_and_show_consent_form()
    else:
        _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")


func _on_consent_info_updated_failure(error) -> void:
    if _shutting_down:
        return
    var message := "UNKNOWN"
    if error != null:
        message = str(error.message)
    ad_error.emit("CONSENT UPDATE FAILED · %s" % message)
    _disable_ads_for_privacy("ADS DISABLED · CONSENT UNAVAILABLE")


func _load_and_show_consent_form() -> void:
    if OS.get_name() != "iOS":
        super._load_and_show_consent_form()
        return
    if _shutting_down or _ads_removed or not _att_allows_tracking():
        return
    UserMessagingPlatform.load_consent_form(
        Callable(self, "_on_consent_form_loaded"),
        Callable(self, "_on_consent_form_load_failed")
    )


func _on_consent_form_loaded(form) -> void:
    if _shutting_down or form == null:
        return
    form.show(Callable(self, "_on_consent_form_dismissed"))


func _on_consent_form_load_failed(error) -> void:
    if _shutting_down:
        return
    var message := "UNKNOWN"
    if error != null:
        message = str(error.message)
    ad_error.emit("CONSENT FORM LOAD FAILED · %s" % message)
    _disable_ads_for_privacy("ADS DISABLED · CONSENT UNAVAILABLE")


func _on_consent_form_dismissed(error) -> void:
    if _shutting_down:
        return
    if error != null:
        ad_error.emit("CONSENT FORM · %s" % str(error.message))
    privacy_options_changed.emit(is_privacy_options_required())
    if _att_allows_tracking() and _consent_allows_ads():
        _initialize_mobile_ads()
    else:
        _disable_ads_for_privacy("ADS DISABLED · CONSENT OR TRACKING PERMISSION REQUIRED")


func _initialize_mobile_ads() -> void:
    if OS.get_name() != "iOS":
        super._initialize_mobile_ads()
        return
    if _shutting_down or _ads_removed or _ads_ready or not _att_allows_tracking() or not _consent_allows_ads():
        return

    ads_state_changed.emit(false, "INITIALIZING ADS")
    var request_configuration := RequestConfiguration.new()
    MobileAds.set_request_configuration(request_configuration)

    _initialization_listener = OnInitializationCompleteListener.new()
    _initialization_listener.on_initialization_complete = Callable(self, "_on_mobile_ads_initialized")
    MobileAds.initialize(_initialization_listener)


func _on_mobile_ads_initialized(_status) -> void:
    if _shutting_down:
        return
    if _ads_removed:
        set_ads_removed(true)
        return
    if not _att_allows_tracking() or not _consent_allows_ads():
        _disable_ads_for_privacy("ADS DISABLED · CONSENT OR TRACKING PERMISSION REQUIRED")
        return
    _ads_ready = true
    ads_state_changed.emit(true, "ADS READY")
    _load_interstitial()


func _load_interstitial() -> void:
    if OS.get_name() != "iOS":
        super._load_interstitial()
        return
    if _shutting_down or _ads_removed or not _ads_ready or not _att_allows_tracking() or not _consent_allows_ads() or _interstitial_ad != null:
        return

    _load_callback = InterstitialAdLoadCallback.new()
    _load_callback.on_ad_failed_to_load = Callable(self, "_on_interstitial_failed_to_load")
    _load_callback.on_ad_loaded = Callable(self, "_on_interstitial_loaded")
    InterstitialAdLoader.new().load(INTERSTITIAL_IOS, AdRequest.new(), _load_callback)


func _on_interstitial_failed_to_load(error) -> void:
    if _shutting_down:
        return
    _interstitial_ad = null
    interstitial_state_changed.emit(false)
    var message := "UNKNOWN"
    if error != null:
        message = str(error.message)
    ad_error.emit("INTERSTITIAL LOAD FAILED · %s" % message)
    if not _ads_removed and _ads_ready and _att_allows_tracking() and _consent_allows_ads() and _retry_timer != null and _retry_timer.is_stopped():
        _retry_timer.start()


func _on_interstitial_loaded(ad) -> void:
    if ad == null:
        return

    # InterstitialAd itself owns a default anonymous `on_ad_paid` lambda.
    # Replace it before retaining the ad so no self-lambda survives to shutdown.
    ad.on_ad_paid = Callable(self, "_on_interstitial_paid")

    if _shutting_down:
        ad.destroy()
        return
    if _ads_removed:
        ad.destroy()
        return
    if not _att_allows_tracking() or not _consent_allows_ads():
        ad.destroy()
        _disable_ads_for_privacy("ADS DISABLED · CONSENT OR TRACKING PERMISSION REQUIRED")
        return

    _interstitial_ad = ad
    _attach_full_screen_callback()
    interstitial_state_changed.emit(true)


func _attach_full_screen_callback() -> void:
    if OS.get_name() != "iOS":
        super._attach_full_screen_callback()
        return
    if _shutting_down or _interstitial_ad == null or _ads_removed:
        return

    # Reuse the callback object already created by InterstitialAd and replace
    # ALL five anonymous defaults, including clicked/impression which were
    # previously left alive until process termination.
    _full_screen_callback = _interstitial_ad.full_screen_content_callback
    if _full_screen_callback == null:
        _full_screen_callback = FullScreenContentCallback.new()

    _full_screen_callback.on_ad_clicked = Callable(self, "_on_interstitial_clicked")
    _full_screen_callback.on_ad_dismissed_full_screen_content = Callable(self, "_on_interstitial_dismissed")
    _full_screen_callback.on_ad_failed_to_show_full_screen_content = Callable(self, "_on_interstitial_failed_to_show")
    _full_screen_callback.on_ad_impression = Callable(self, "_on_interstitial_impression")
    _full_screen_callback.on_ad_showed_full_screen_content = Callable(self, "_on_interstitial_showed")
    _interstitial_ad.full_screen_content_callback = _full_screen_callback


func _on_interstitial_clicked() -> void:
    pass


func _on_interstitial_impression() -> void:
    pass


func _on_interstitial_paid(_ad_value) -> void:
    pass


func _on_interstitial_showed() -> void:
    if not _shutting_down:
        interstitial_state_changed.emit(false)


func _on_interstitial_dismissed() -> void:
    if not _shutting_down:
        _finish_interstitial()


func _on_interstitial_failed_to_show(error) -> void:
    if _shutting_down:
        return
    var message := "UNKNOWN"
    if error != null:
        message = str(error.message)
    ad_error.emit("INTERSTITIAL SHOW FAILED · %s" % message)
    _finish_interstitial()


func _notification(what: int) -> void:
    if OS.get_name() != "iOS":
        return

    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT or what == MainLoop.NOTIFICATION_APPLICATION_PAUSED:
        _shutting_down = true
        if _retry_timer != null and not _retry_timer.is_stopped():
            _retry_timer.stop()
        return

    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN or what == MainLoop.NOTIFICATION_APPLICATION_RESUMED:
        _shutting_down = false
        _consent_information = UserMessagingPlatform.consent_information
        if _ads_removed:
            return

        var tracking_allowed := _att_allows_tracking()
        if not tracking_allowed:
            if _ads_ready:
                _disable_ads_for_privacy("ADS DISABLED · TRACKING PERMISSION NOT GRANTED")
            return

        # If the user changed ATT authorization in iOS Settings after declining,
        # allow the advertising stack to start cleanly on return to the app.
        if _started and not _ads_ready and not _att_request_in_flight:
            _started = false
            call_deferred("start_ads")
            return

        if _ads_ready and _interstitial_ad == null:
            call_deferred("_load_interstitial")


func _exit_tree() -> void:
    if OS.get_name() != "iOS":
        super._exit_tree()
        return

    _shutting_down = true
    _att_request_in_flight = false
    if _att != null:
        var permission_callback := Callable(self, "_on_att_permission_result")
        if _att.permission_result.is_connected(permission_callback):
            _att.permission_result.disconnect(permission_callback)
    _att = null
    _initialization_listener = null
    _load_callback = null
    _full_screen_callback = null

    if _interstitial_ad != null:
        _interstitial_ad.on_ad_paid = Callable()

    super._exit_tree()
