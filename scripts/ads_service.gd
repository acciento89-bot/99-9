extends Node

signal ads_state_changed(ready: bool, message: String)
signal interstitial_state_changed(ready: bool)
signal interstitial_closed
signal ad_error(message: String)

const TEST_INTERSTITIAL_ANDROID := "ca-app-pub-3940256099942544/1033173712"
const TEST_INTERSTITIAL_IOS := "ca-app-pub-3940256099942544/4411468910"

var _started := false
var _ads_ready := false
var _interstitial_ad = null
var _consent_update_listener = null
var _consent_dismiss_listener = null
var _initialization_listener = null
var _load_callback = null
var _full_screen_callback = null
var _retry_timer: Timer


func _ready() -> void:
    _retry_timer = Timer.new()
    _retry_timer.one_shot = true
    _retry_timer.wait_time = 20.0
    _retry_timer.timeout.connect(_load_interstitial)
    add_child(_retry_timer)


func start_ads() -> void:
    if _started:
        return
    _started = true

    if OS.get_name() not in ["iOS", "Android"]:
        ads_state_changed.emit(false, "ADS DISABLED ON THIS PLATFORM")
        return

    ads_state_changed.emit(false, "CHECKING PRIVACY CONSENT")
    _request_user_consent()


func is_ads_ready() -> bool:
    return _ads_ready


func is_interstitial_ready() -> bool:
    return _interstitial_ad != null


func show_interstitial_if_ready() -> bool:
    if _interstitial_ad == null:
        if _ads_ready:
            _load_interstitial()
        return false

    interstitial_state_changed.emit(false)
    _interstitial_ad.show()
    return true


func _request_user_consent() -> void:
    var params := ConsentRequestParameters.new()
    _consent_update_listener = OnConsentInfoUpdateListener.new()

    _consent_update_listener.on_consent_info_update_success = func() -> void:
        if ConsentInformation.is_consent_form_available():
            _load_and_show_consent_form()
        else:
            _initialize_mobile_ads()

    _consent_update_listener.on_consent_info_update_failure = func(error: FormError) -> void:
        # A transient UMP failure must not brick the game. The SDK can still use
        # any previously stored consent state. Production remains gated by the
        # AdMob privacy-message configuration before live ad units are enabled.
        ad_error.emit("CONSENT UPDATE FAILED · %s" % error.message)
        _initialize_mobile_ads()

    ConsentInformation.request_consent_info_update(params, _consent_update_listener)


func _load_and_show_consent_form() -> void:
    _consent_dismiss_listener = OnConsentFormDismissedListener.new()
    _consent_dismiss_listener.on_consent_form_dismissed = func(error: FormError) -> void:
        if error != null:
            ad_error.emit("CONSENT FORM · %s" % error.message)
        _initialize_mobile_ads()

    ConsentForm.load_and_show_consent_form_if_required(_consent_dismiss_listener)


func _initialize_mobile_ads() -> void:
    if _ads_ready:
        return

    ads_state_changed.emit(false, "INITIALIZING TEST ADS")
    var request_configuration := RequestConfiguration.new()
    MobileAds.set_request_configuration(request_configuration)

    _initialization_listener = OnInitializationCompleteListener.new()
    _initialization_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
        _ads_ready = true
        ads_state_changed.emit(true, "TEST ADS READY")
        _load_interstitial()

    MobileAds.initialize(_initialization_listener)


func _load_interstitial() -> void:
    if not _ads_ready or _interstitial_ad != null:
        return

    var unit_id := TEST_INTERSTITIAL_ANDROID if OS.get_name() == "Android" else TEST_INTERSTITIAL_IOS
    _load_callback = InterstitialAdLoadCallback.new()

    _load_callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
        _interstitial_ad = null
        interstitial_state_changed.emit(false)
        ad_error.emit("INTERSTITIAL LOAD FAILED · %s" % error.message)
        if _retry_timer.is_stopped():
            _retry_timer.start()

    _load_callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
        _interstitial_ad = ad
        _attach_full_screen_callback()
        interstitial_state_changed.emit(true)

    InterstitialAdLoader.new().load(unit_id, AdRequest.new(), _load_callback)


func _attach_full_screen_callback() -> void:
    if _interstitial_ad == null:
        return

    _full_screen_callback = FullScreenContentCallback.new()
    _full_screen_callback.on_ad_showed_full_screen_content = func() -> void:
        interstitial_state_changed.emit(false)

    _full_screen_callback.on_ad_dismissed_full_screen_content = func() -> void:
        _finish_interstitial()

    _full_screen_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
        ad_error.emit("INTERSTITIAL SHOW FAILED · %s" % error.message)
        _finish_interstitial()

    _interstitial_ad.full_screen_content_callback = _full_screen_callback


func _finish_interstitial() -> void:
    if _interstitial_ad != null:
        _interstitial_ad.destroy()
        _interstitial_ad = null
    interstitial_state_changed.emit(false)
    interstitial_closed.emit()
    _load_interstitial()


func _exit_tree() -> void:
    if _interstitial_ad != null:
        _interstitial_ad.destroy()
        _interstitial_ad = null
