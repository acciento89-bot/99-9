extends RefCounted
const Practice = preload("res://scripts/practice_model.gd")
const MAX_BYTES := 256 * 1024
const FORMAT := "ninenine.practice"
static var _gate: Mutex = Mutex.new()
var _path: String
var _writer: Callable

func _init(path: String, writer: Callable = Callable()) -> void:
    _path = ProjectSettings.globalize_path(path)
    _writer = writer if writer.is_valid() else _atomic_write

static func _bad(message: String) -> Dictionary:
    return {"ok": false, "error": message}

static func encode(book: Dictionary) -> Dictionary:
    if not Practice.validate(book).ok: return _bad("Invalid practice journal")
    # Numeric JSON parsing can shave bits even with full_precision output.
    # Preserve doubles as exact IEEE-754 little-endian hex, never remeasure.
    var payload := JSON.stringify(_wire(book), "", true, true)
    var envelope := {"format": FORMAT, "schema": 1, "payload": payload, "sha256": payload.sha256_text()}
    var bytes := JSON.stringify(envelope, "", true, true).to_utf8_buffer()
    if bytes.is_empty() or bytes.size() > MAX_BYTES: return _bad("Practice journal size limit")
    var verified: Dictionary = decode(bytes)
    if not verified.ok or verified.book != book: return _bad("Practice encoding could not preserve exact facts")
    return {"ok": true, "bytes": bytes}

static func _wire(value: Variant) -> Variant:
    if typeof(value) == TYPE_FLOAT:
        var bytes := PackedByteArray()
        bytes.resize(8)
        bytes.encode_double(0, value)
        return {"f64": bytes.hex_encode()}
    if typeof(value) == TYPE_DICTIONARY:
        var mapped: Dictionary = {}
        for key in value: mapped[key] = _wire(value[key])
        return mapped
    if typeof(value) == TYPE_ARRAY:
        var mapped: Array = []
        for item in value: mapped.append(_wire(item))
        return mapped
    return value

static func _unwire(value: Variant) -> Dictionary:
    # A parse failure must never become an ordinary nullable journal field.
    if typeof(value) == TYPE_DICTIONARY:
        if value.has("f64"):
            if value.size() != 1 or typeof(value.f64) != TYPE_STRING or value.f64.length() != 16: return _bad("Malformed measured number")
            for character in value.f64:
                if not character in "0123456789abcdef": return _bad("Malformed measured number")
            var bytes: PackedByteArray = value.f64.hex_decode()
            if bytes.size() != 8 or bytes.hex_encode() != value.f64: return _bad("Malformed measured number")
            return {"ok": true, "value": bytes.decode_double(0)}
        var mapped: Dictionary = {}
        for key in value:
            var child: Dictionary = _unwire(value[key])
            if not child.ok: return child
            mapped[key] = child.value
        return {"ok": true, "value": mapped}
    if typeof(value) == TYPE_ARRAY:
        var mapped: Array = []
        for item in value:
            var child: Dictionary = _unwire(item)
            if not child.ok: return child
            mapped.append(child.value)
        return {"ok": true, "value": mapped}
    return {"ok": true, "value": value}

static func decode(bytes: PackedByteArray) -> Dictionary:
    if bytes.is_empty() or bytes.size() > MAX_BYTES: return _bad("Practice journal size limit")
    var text := bytes.get_string_from_utf8()
    if text.to_utf8_buffer() != bytes: return _bad("Invalid practice UTF8")
    var parser := JSON.new()
    if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY: return _bad("Damaged practice journal")
    var envelope: Dictionary = parser.data
    if envelope.get("format") != FORMAT or envelope.get("schema") != 1 or typeof(envelope.get("payload")) != TYPE_STRING or typeof(envelope.get("sha256")) != TYPE_STRING:
        return _bad("Unsupported practice journal")
    var payload: String = envelope.payload
    if payload.is_empty() or payload.sha256_text() != envelope.sha256: return _bad("Practice journal checksum mismatch")
    var contents := JSON.new()
    if contents.parse(payload) != OK: return _bad("Invalid practice records")
    var unwired: Dictionary = _unwire(contents.data)
    if not unwired.ok: return unwired
    var facts: Variant = unwired.value
    if not Practice.validate(facts).ok: return _bad("Invalid practice records")
    # Godot JSON represents integral counters as FLOAT Variants. Restore only
    # validated whole-number counter/identity fields; never round measured
    # phase, percentage, signed milliseconds or mean absolute timing error.
    var book: Dictionary = facts
    _restore_integer_fields(book)
    return {"ok": true, "book": book}

static func _summary_integer_fields(summary_value: Dictionary) -> void:
    summary_value.hits = int(summary_value.hits)
    for outcome in summary_value.outcomes: outcome.stage = int(outcome.stage)

static func _restore_integer_fields(book: Dictionary) -> void:
    book.schema = int(book.schema)
    book.revision = int(book.revision)
    for record_value in book.records:
        record_value.stage = int(record_value.stage)
        record_value.sessions = int(record_value.sessions)
        _summary_integer_fields(record_value.best)
        for summary_value in record_value.history: _summary_integer_fields(summary_value)
    if book.active != null:
        book.active.stage = int(book.active.stage)
        book.active.round.stage = int(book.active.round.stage)
        for outcome in book.active.outcomes: outcome.stage = int(outcome.stage)

func read_book() -> Dictionary:
    _gate.lock()
    var result: Dictionary = _read_unlocked()
    _gate.unlock()
    return result

func _read_unlocked() -> Dictionary:
    if not FileAccess.file_exists(_path): return {"ok": true, "book": Practice.empty_book()}
    var read: Dictionary = _read_bytes()
    if not read.ok: return read
    return decode(read.bytes)

func _read_bytes() -> Dictionary:
    var file := FileAccess.open(_path, FileAccess.READ)
    if file == null: return _bad("Practice journal cannot be read")
    var length := file.get_length()
    if length < 1 or length > MAX_BYTES:
        file.close()
        return _bad("Practice journal size limit")
    var bytes := file.get_buffer(length)
    var complete := bytes.size() == length and file.get_length() == length
    file.close()
    if not complete: return _bad("Practice journal changed while reading")
    return {"ok": true, "bytes": bytes}

func save_book(book: Dictionary, expected_revision: int) -> Dictionary:
    var encoded: Dictionary = encode(book)
    if not encoded.ok: return encoded
    _gate.lock()
    var result: Dictionary = _save_unlocked(book, expected_revision, encoded.bytes)
    _gate.unlock()
    return result

func _save_unlocked(book: Dictionary, expected_revision: int, bytes: PackedByteArray) -> Dictionary:
    # Decode the CURRENT disk payload before any retry or replacement. Never
    # turn an externally damaged/future journal into an empty writable book.
    var current: Dictionary = _read_unlocked()
    if not current.ok: return current
    if FileAccess.file_exists(_path):
        var existing: Dictionary = _read_bytes()
        if not existing.ok: return existing
        if existing.bytes == bytes: return {"ok": true, "book": book.duplicate(true)}
    if expected_revision < 0 or expected_revision >= Practice.MAX_REVISION or current.book.revision != expected_revision or book.revision != expected_revision + 1:
        return _bad("Practice journal changed; reload saved progress")
    var write_result: Variant = _writer.call(_path, bytes)
    # The writer can commit and then report an error; exact verified bytes are
    # the receipt. The UI may publish only after this read-back succeeds.
    var after: Dictionary = _read_bytes() if FileAccess.file_exists(_path) else _bad("Missing practice commit")
    if after.ok and after.bytes == bytes and decode(after.bytes).ok:
        return {"ok": true, "book": book.duplicate(true)}
    if typeof(write_result) != TYPE_INT or int(write_result) != OK: return _bad("Practice save failed; previous state kept")
    return _bad("Practice commit could not be verified")

static func _atomic_write(path: String, bytes: PackedByteArray) -> Error:
    var directory := path.get_base_dir()
    var created := DirAccess.make_dir_recursive_absolute(directory)
    if created != OK and created != ERR_ALREADY_EXISTS: return created
    var entropy := Crypto.new().generate_random_bytes(12)
    if entropy.size() != 12: return ERR_CANT_CREATE
    var temporary := directory.path_join(".practice-" + entropy.hex_encode() + ".tmp")
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null: return FileAccess.get_open_error()
    file.store_buffer(bytes)
    file.flush()
    var error := file.get_error()
    file.close()
    if error == OK and FileAccess.get_file_as_bytes(temporary) != bytes: error = ERR_FILE_CORRUPT
    # Same directory, no delete-first fallback. Mobile filesystem semantics and
    # power-loss durability remain actual root platform acceptance gates.
    if error == OK: error = DirAccess.rename_absolute(temporary, path)
    if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
    return error
