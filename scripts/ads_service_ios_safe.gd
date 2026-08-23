extends "res://scripts/ads_service.gd"

# iOS foreground-termination guard.
# When the app switcher is opened directly from gameplay, iOS first resigns
# active and may terminate the process immediately afterwards. Mark the native
# ad bridge as shutting down at that first lifecycle notification so late
# Google Mobile Ads / UMP callbacks cannot touch Godot while iOS tears down.

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
        if _ads_ready and _interstitial_ad == null:
            call_deferred("_load_interstitial")
