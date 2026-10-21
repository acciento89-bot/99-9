extends SceneTree
const Practice = preload("res://scripts/practice_model.gd")
const Archive = preload("res://scripts/practice_archive.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("FAIL " + message)
func write_bytes(path: String, bytes: PackedByteArray) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null: return FileAccess.get_open_error()
    file.store_buffer(bytes)
    file.flush()
    var error := file.get_error()
    file.close()
    return error
func diagnose(expected: Variant, actual: Variant, path: String) -> void:
    if typeof(expected) == TYPE_DICTIONARY and typeof(actual) == TYPE_DICTIONARY:
        for key in expected:
            if not actual.has(key): print("DIFF missing ", path, ".", key)
            else: diagnose(expected[key], actual[key], path + "." + str(key))
        return
    if typeof(expected) == TYPE_ARRAY and typeof(actual) == TYPE_ARRAY:
        if expected.size() != actual.size(): print("DIFF length ", path)
        for i in range(mini(expected.size(), actual.size())): diagnose(expected[i], actual[i], path + "[" + str(i) + "]")
        return
    if typeof(expected) != typeof(actual) or expected != actual:
        print("DIFF ", path, " expected_type=", typeof(expected), " actual_type=", typeof(actual), " expected=", expected, " actual=", actual,
            " expected_bytes=", var_to_bytes(expected).hex_encode(), " actual_bytes=", var_to_bytes(actual).hex_encode())
func _initialize() -> void:
    var directory: String = OS.get_cmdline_user_args()[0]
    var path := directory.path_join("practice.json")
    var legacy := directory.path_join("save.json")
    var sentinel := "existing scores/themes/removeads byte sentinel".to_utf8_buffer()
    write_bytes(legacy, sentinel)
    var archive = Archive.new(path)
    var initial: Dictionary = archive.read_book()
    check(initial.ok and initial.book.revision == 0 and not FileAccess.file_exists(path), "missing practice journal never writes or migrates legacy")
    var first: Dictionary = Practice.begin(initial.book, 1, "archive-session", "archive-round").book
    check(archive.save_book(first, 0).ok, "actual first atomic save")
    var readback: Dictionary = Archive.new(path).read_book()
    if not readback.ok: print("DIFF disk decode error ", readback)
    elif readback.book != first: diagnose(first, readback.book, "restart")
    check(readback.ok and readback.book == first, "exact actual production codec/disk restart")
    var bytes := FileAccess.get_file_as_bytes(path)
    check(not archive.save_book(initial.book, 0).ok and FileAccess.get_file_as_bytes(path) == bytes, "stale revision cannot overwrite committed journal")
    var next: Dictionary = Practice.checkpoint(first, "archive-session", "archive-round", Practice.start_round(first.active.round).round).book
    check(archive.save_book(next, 1).ok and archive.read_book().book.revision == 2, "actual replacement save without deleting previous path")
    var current_round: Dictionary = Practice.tick(next.active.round, 0.0, true).round
    current_round = Practice.tick(current_round, .123456789012345, true).round
    var third: Dictionary = Practice.checkpoint(next, "archive-session", "archive-round", current_round).book
    var before_failure = Archive.new(path, func(_path: String, _bytes: PackedByteArray) -> Error: return ERR_CANT_CREATE)
    check(not before_failure.save_book(third, 2).ok and archive.read_book().book.revision == 2, "failed write never publishes requested state")
    var after_commit = Archive.new(path, func(target: String, payload: PackedByteArray) -> Error:
        write_bytes(target, payload)
        return ERR_CANT_CREATE
    )
    check(after_commit.save_book(third, 2).ok and archive.read_book().book.revision == 3, "exact successful commit receipt survives writer error")
    var precision_regression: Dictionary = Practice.record(third, "archive-session", "archive-round", 0.253344).book
    var precision_encoded: Dictionary = Archive.encode(precision_regression)
    check(precision_encoded.ok and Archive.decode(precision_encoded.bytes).book == precision_regression, "actual UI regression phase/error/value round trip bit-exact before any write")
    var stopped: Dictionary = Practice.record(third, "archive-session", "archive-round", 2.0).book
    var encoded: Dictionary = Archive.encode(stopped)
    var decoded: Dictionary = Archive.decode(encoded.bytes)
    if not decoded.ok: print("DIFF measured decode error ", decoded)
    elif decoded.book != stopped: diagnose(stopped, decoded.book, "measured")
    check(encoded.ok and decoded.ok and decoded.book == stopped, "actual precise JSON round trip incl measured phase/signed error/outcome/token")
    var raw := "broken practice".to_utf8_buffer()
    write_bytes(path, raw)
    check(not archive.read_book().ok and not archive.save_book(first, 0).ok and FileAccess.get_file_as_bytes(path) == raw, "corrupt current bytes visible and preserved")
    var future: Dictionary = third.duplicate(true)
    future.schema = 99
    check(not Archive.encode(future).ok, "future model cannot write")
    raw = JSON.stringify({"format": "ninenine.practice", "schema": 99, "payload": "", "sha256": ""}).to_utf8_buffer()
    write_bytes(path, raw)
    check(not archive.read_book().ok and not archive.save_book(first, 0).ok and FileAccess.get_file_as_bytes(path) == raw, "future envelope cannot be reset")
    check(not Archive.decode("{}".to_utf8_buffer()).ok and not Archive.decode("null".to_utf8_buffer()).ok, "missing fields cannot normalize into fresh archive")
    var malformed_payload := JSON.stringify({"schema": 1, "revision": 1, "records": [], "active": {"f64": "xyzxyzxyzxyzxyzx"}})
    var malformed_bytes := JSON.stringify({"format": "ninenine.practice", "schema": 1, "payload": malformed_payload, "sha256": malformed_payload.sha256_text()}).to_utf8_buffer()
    check(not Archive.decode(malformed_bytes).ok, "malformed float cannot become legitimate empty active session")
    write_bytes(path, malformed_bytes)
    var replacement: Dictionary = Practice.empty_book()
    replacement.revision = 2
    check(not archive.read_book().ok and not archive.save_book(replacement, 1).ok and FileAccess.get_file_as_bytes(path) == malformed_bytes, "malformed float current archive blocks replacement and preserves exact bytes")
    var too_large := PackedByteArray()
    too_large.resize(256 * 1024 + 1)
    write_bytes(path, too_large)
    check(not archive.read_book().ok and not Archive.decode(too_large).ok, "oversized file rejected before deserialize")
    check(FileAccess.get_file_as_bytes(legacy) == sentinel, "original score/theme/IAP save exact bytes untouched")
    if failures == 0: print("NN PRACTICE ARCHIVE PASS checks=", checks)
    quit(0 if failures == 0 else 1)
