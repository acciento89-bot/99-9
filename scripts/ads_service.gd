extends Node

signal ads_state_changed(ready: bool, message: String)
signal interstitial_state_changed(ready: bool)
signal interstitial_closed
signal privacy_options_changed(required: bool)
signal ad_error(message: String)

const TEST_INTERSTITIAL_ANDROID := "ca-app-pub-3940256099942544/1033173712"
const TEST_INTERSTITIAL_IOS := "ca-app-pub-3940256099942544/4411468910"

var _started := false
var _ads_ready := false
var _interstitial_ad = null
var _initialization_listener = null
var _load_callback = null
var _full_screen_callback = null
var _consent_information: ConsentInformation
var _retry_timer: Timer


func _ready() -> void:
    _consent_information = UserMessagingPlatform.consent_information
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


func is_privacy_options_required() -> bool:
    if OS.get_name() not in ["iOS", "Android"] or _consent_information == null:
        return false
    return _consent_information.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
    if OS.get_name() not in ["iOS", "Android"]:
        return

    UserMessagingPlatform.show_privacy_options_form(func(error: FormError) -> void:
        if error != null:
            ad_error.emit("PRIVACY OPTIONS · %s" % error.message)
        privacy_options_changed.emit(is_privacy_options_required())
        if _consent_allows_ads():
            if not _ads_ready:
                _initialize_mobile_ads()
        else:
            _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")
    )


func show_interstitial_if_ready() -> bool:
    if not _consent_allows_ads():
        _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")
        return false

    if _interstitial_ad == null:
        if _ads_ready:
            _load_interstitial()
        return false

    interstitial_state_changed.emit(false)
    _interstitial_ad.show()
    return true


func _request_user_consent() -> void:
    var params := ConsentRequestParameters.new()
    _consent_information.update(
        params,
        func() -> void:
            privacy_options_changed.emit(is_privacy_options_required())
            if _consent_allows_ads():
                _initialize_mobile_ads()
            elif _consent_information.get_is_consent_form_available():
                _load_and_show_consent_form()
            else:
                _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED"),
        func(error: FormError) -> void:
            ad_error.emit("CONSENT UPDATE FAILED · %s" % error.message)
            _disable_ads_for_privacy("ADS DISABLED · CONSENT UNAVAILABLE")
    )


func _load_and_show_consent_form() -> void:
    UserMessagingPlatform.load_consent_form(
        func(form: ConsentForm) -> void:
            form.show(func(error: FormError) -> void:
                if error != null:
                    ad_error.emit("CONSENT FORM · %s" % error.message)
                privacy_options_changed.emit(is_privacy_options_required())
                if _consent_allows_ads():
                    _initialize_mobile_ads()
                else:
                    _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")
            ),
        func(error: FormError) -> void:
            ad_error.emit("CONSENT FORM LOAD FAILED · %s" % error.message)
            _disable_ads_for_privacy("ADS DISABLED · CONSENT UNAVAILABLE")
    )


func _consent_allows_ads() -> bool:
    if _consent_information == null:
        return false
    var status := _consent_information.get_consent_status()
    return status == ConsentInformation.ConsentStatus.NOT_REQUIRED or status == ConsentInformation.ConsentStatus.OBTAINED


func _disable_ads_for_privacy(message: String) -> void:
    _ads_ready = false
    if _retry_timer != null and not _retry_timer.is_stopped():
        _retry_timer.stop()
    if _interstitial_ad != null:
        _interstitial_ad.destroy()
        _interstitial_ad = null
    interstitial_state_changed.emit(false)
    ads_state_changed.emit(false, message)


func _initialize_mobile_ads() -> void:
    if _ads_ready or not _consent_allows_ads():
        return

    ads_state_changed.emit(false, "INITIALIZING TEST ADS")
    var request_configuration := RequestConfiguration.new()
    MobileAds.set_request_configuration(request_configuration)

    _initialization_listener = OnInitializationCompleteListener.new()
    _initialization_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
        if not _consent_allows_ads():
            _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")
            return
        _ads_ready = true
        ads_state_changed.emit(true, "TEST ADS READY")
        _load_interstitial()

    MobileAds.initialize(_initialization_listener)


func _load_interstitial() -> void:
    if not _ads_ready or not _consent_allows_ads() or _interstitial_ad != null:
        return

    var unit_id := TEST_INTERSTITIAL_ANDROID if OS.get_name() == "Android" else TEST_INTERSTITIAL_IOS
    _load_callback = InterstitialAdLoadCallback.new()

    _load_callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
        _interstitial_ad = null
        interstitial_state_changed.emit(false)
        ad_error.emit("INTERSTITIAL LOAD FAILED · %s" % error.message)
        if _ads_ready and _consent_allows_ads() and _retry_timer.is_stopped():
            _retry_timer.start()

    _load_callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
        if not _consent_allows_ads():
            ad.destroy()
            _disable_ads_for_privacy("ADS DISABLED · CONSENT REQUIRED")
            return
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
