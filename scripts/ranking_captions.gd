extends RefCounted
# Keep the Android cross-platform explanation. Apple-facing captions are neutral.
static func menu(platform: String) -> String:
    return "GLOBAL RANKINGS" if platform == "iOS" else "GLOBAL RANKINGS · iOS + ANDROID"

static func ranking(platform: String) -> String:
    return "GLOBAL RANKINGS" if platform == "iOS" else "GLOBAL · iOS + ANDROID"
