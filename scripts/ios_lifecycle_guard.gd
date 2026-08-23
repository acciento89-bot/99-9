extends Node

signal app_suspending
signal app_resumed

var suspending := false

func _notification(what: int) -> void:
    match what:
        MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_PAUSED:
            if not suspending:
                suspending = true
                app_suspending.emit()
        MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_RESUMED:
            if suspending:
                suspending = false
                app_resumed.emit()
