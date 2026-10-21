extends RefCounted
# Local practice facts only. No Node, provider, player-score or file dependencies.
const MAX_REVISION := 1000000000
const SESSION_LENGTH := 12
const QUALIFY_HITS := 8

static func _bad(message: String) -> Dictionary:
    return {"ok": false, "error": message}

static func _finite(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _whole(value: Variant, low: int, high: int) -> bool:
    return _finite(value) and float(value) >= low and float(value) <= high and float(value) == floorf(float(value))

static func _token(value: Variant) -> bool:
    if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64:
        return false
    for character in value:
        if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"):
            return false
    return true

static func catalog() -> Array:
    var result: Array = []
    var targets := [75.0, 75.0, 90.0, 90.0, 99.0, 99.0, 99.9, 100.0]
    var speeds := [1.2, 1.2, 1.5, 1.5, 1.8, 1.8, 2.1, 2.45]
    var windows := [1.0, 1.0, .6, .6, .15, .15, .05, .005]
    for i in range(8):
        var direction := "peak" if i == 7 else ("falling" if i in [1, 3, 5] else "rising")
        var phase := acos(1.0 - float(targets[i]) / 50.0)
        if direction == "falling": phase = TAU - phase
        result.append({"id": i + 1, "target": targets[i], "speed": speeds[i], "window": windows[i], "direction": direction, "target_phase": phase})
    return result

static func evaluate(stage: int, phase: float) -> Dictionary:
    if stage < 1 or stage > 8 or not is_finite(phase) or phase < 0.0 or phase > TAU:
        return _bad("Invalid practice stop")
    var definition: Dictionary = catalog()[stage - 1]
    var value := 50.0 - 50.0 * cos(phase)
    var correct_direction: bool = definition.direction == "peak" or (phase <= PI if definition.direction == "rising" else phase >= PI)
    var signed_ms: float = (phase - float(definition.target_phase)) / float(definition.speed) * 1000.0
    return {"ok": true, "stage": stage, "phase": phase, "value": value, "signed_ms": signed_ms,
        "hit": correct_direction and absf(value - float(definition.target)) <= float(definition.window),
        "timing": "on_time" if absf(signed_ms) < .000001 else ("early" if signed_ms < 0 else "late")}

static func create_round(stage: int, identity: String) -> Dictionary:
    if stage < 1 or stage > 8 or not _token(identity): return _bad("Invalid practice round")
    return {"ok": true, "round": {"id": identity, "stage": stage, "phase": 0.0, "state": "ready", "anchored": false}}

static func _round_valid(value: Variant) -> bool:
    if typeof(value) != TYPE_DICTIONARY: return false
    if not _token(value.get("id")) or not _whole(value.get("stage"), 1, 8) or not _finite(value.get("phase")): return false
    if float(value.phase) < 0 or float(value.phase) > TAU or typeof(value.get("anchored")) != TYPE_BOOL: return false
    if value.get("state") not in ["ready", "running", "paused", "expired", "result"]: return false
    if value.state == "ready" and (value.phase != 0 or value.anchored): return false
    if value.state == "expired" and value.phase != TAU: return false
    return true

static func start_round(value: Dictionary) -> Dictionary:
    if not _round_valid(value) or value.state != "ready": return _bad("Round is not ready")
    var next: Dictionary = value.duplicate(true)
    next.state = "running"
    next.anchored = false
    return {"ok": true, "round": next}

static func resume_round(value: Dictionary) -> Dictionary:
    if not _round_valid(value) or value.state != "paused": return _bad("Round is not paused")
    var next: Dictionary = value.duplicate(true)
    next.state = "running"
    next.anchored = false
    return {"ok": true, "round": next}

static func tick(value: Dictionary, delta: float, active: bool) -> Dictionary:
    if not _round_valid(value) or not is_finite(delta) or delta < 0: return _bad("Invalid practice clock")
    var next: Dictionary = value.duplicate(true)
    if next.state != "running": return {"ok": true, "round": next}
    if not active:
        next.state = "paused"
        next.anchored = false
    elif not next.anchored:
        next.anchored = true
    else:
        var speed: float = catalog()[int(next.stage) - 1].speed
        # Limit before multiplication, so a finite huge delta cannot overflow.
        next.phase = minf(TAU, float(next.phase) + minf(delta, TAU / speed) * speed)
        if next.phase >= TAU:
            next.state = "expired"
            next.anchored = false
    return {"ok": true, "round": next}

static func empty_book() -> Dictionary:
    return {"schema": 1, "revision": 0, "records": [], "active": null}

static func unlocked(book: Dictionary, stage: int) -> bool:
    if stage < 1 or stage > 8: return false
    if stage == 1: return true
    for record_value in book.get("records", []):
        if int(record_value.stage) == stage - 1 and record_value.qualified: return true
    return false

static func _outcome_valid(value: Variant, stage: int) -> bool:
    if typeof(value) != TYPE_DICTIONARY or not _token(value.get("round_id")) or not _finite(value.get("phase")): return false
    var expected: Dictionary = evaluate(stage, float(value.phase))
    if not expected.ok: return false
    for field in ["stage", "value", "signed_ms", "hit", "timing"]:
        if not value.has(field) or value[field] != expected[field]: return false
    return true

static func _summary(identity: String, outcomes: Array) -> Dictionary:
    var hits := 0
    var absolute := 0.0
    for outcome in outcomes:
        if outcome.hit: hits += 1
        absolute += absf(float(outcome.signed_ms))
    return {"session_id": identity, "hits": hits, "mean_abs_ms": absolute / SESSION_LENGTH, "outcomes": outcomes.duplicate(true)}

static func _summary_valid(value: Variant, stage: int) -> bool:
    if typeof(value) != TYPE_DICTIONARY or not _token(value.get("session_id")) or typeof(value.get("outcomes")) != TYPE_ARRAY or value.outcomes.size() != SESSION_LENGTH: return false
    var ids: Dictionary = {}
    for outcome in value.outcomes:
        if not _outcome_valid(outcome, stage) or ids.has(outcome.round_id): return false
        ids[outcome.round_id] = true
    var expected: Dictionary = _summary(value.session_id, value.outcomes)
    return _whole(value.get("hits"), 0, SESSION_LENGTH) and _finite(value.get("mean_abs_ms")) and value.hits == expected.hits and absf(float(value.mean_abs_ms) - float(expected.mean_abs_ms)) < .000000001

static func validate(book: Variant) -> Dictionary:
    if typeof(book) != TYPE_DICTIONARY or book.get("schema") != 1 or not _whole(book.get("revision"), 0, MAX_REVISION) or typeof(book.get("records")) != TYPE_ARRAY or not book.has("active"):
        return _bad("Invalid or future practice journal")
    if book.records.size() > 8: return _bad("Practice record limit")
    var ids: Dictionary = {}
    for record_value in book.records:
        if typeof(record_value) != TYPE_DICTIONARY or not _whole(record_value.get("stage"), 1, 8) or ids.has(record_value.stage): return _bad("Invalid practice stage")
        ids[record_value.stage] = true
        var stage := int(record_value.stage)
        if not _whole(record_value.get("sessions"), 1, 1000000) or typeof(record_value.get("qualified")) != TYPE_BOOL or not _summary_valid(record_value.get("best"), stage): return _bad("Invalid practice best")
        if record_value.qualified != (record_value.best.hits >= QUALIFY_HITS) or typeof(record_value.get("history")) != TYPE_ARRAY or record_value.history.is_empty() or record_value.history.size() > 5 or record_value.sessions < record_value.history.size(): return _bad("Invalid practice history")
        var session_ids: Dictionary = {}
        for summary_value in record_value.history:
            if not _summary_valid(summary_value, stage) or session_ids.has(summary_value.session_id): return _bad("Invalid practice session")
            session_ids[summary_value.session_id] = true
            if summary_value.hits > record_value.best.hits or (summary_value.hits == record_value.best.hits and summary_value.mean_abs_ms < record_value.best.mean_abs_ms): return _bad("Best is below recent result")
        if not unlocked(book, stage): return _bad("Locked stage record")
    var active_value = book.active
    if active_value != null:
        if typeof(active_value) != TYPE_DICTIONARY or not _token(active_value.get("session_id")) or not _whole(active_value.get("stage"), 1, 8) or not unlocked(book, int(active_value.stage)) or not _round_valid(active_value.get("round")) or active_value.round.stage != active_value.stage or active_value.get("state") not in ["active", "complete", "abandoned"] or typeof(active_value.get("outcomes")) != TYPE_ARRAY or active_value.outcomes.size() > SESSION_LENGTH: return _bad("Invalid active practice session")
        var round_ids: Dictionary = {}
        for outcome in active_value.outcomes:
            if not _outcome_valid(outcome, int(active_value.stage)) or round_ids.has(outcome.round_id): return _bad("Invalid active outcomes")
            round_ids[outcome.round_id] = true
        if active_value.state == "complete" and active_value.outcomes.size() != SESSION_LENGTH: return _bad("Incomplete session marked complete")
        if active_value.state == "active" and active_value.outcomes.size() == SESSION_LENGTH: return _bad("Completed session marked active")
        if active_value.round.state == "result":
            if active_value.outcomes.is_empty() or active_value.outcomes.back().round_id != active_value.round.id or active_value.outcomes.back().phase != active_value.round.phase: return _bad("Result receipt mismatch")
        elif round_ids.has(active_value.round.id): return _bad("Round identity reused")
    return {"ok": true}

static func _advance(book: Dictionary) -> Dictionary:
    if int(book.revision) >= MAX_REVISION: return _bad("Practice revision limit")
    var next: Dictionary = book.duplicate(true)
    next.revision = int(book.revision) + 1
    return {"ok": true, "book": next}

static func begin(book: Dictionary, stage: int, session_id: String, round_id: String) -> Dictionary:
    if not validate(book).ok or not unlocked(book, stage) or not _token(session_id): return _bad("Practice stage unavailable")
    if book.active != null and (book.active.state == "active" or book.active.session_id == session_id): return _bad("Resume or end the current practice session")
    var round_response: Dictionary = create_round(stage, round_id)
    if not round_response.ok: return round_response
    var response: Dictionary = _advance(book)
    if not response.ok: return response
    response.book.active = {"session_id": session_id, "stage": stage, "state": "active", "round": round_response.round, "outcomes": []}
    return response

static func _current(book: Dictionary, session_id: String, round_id: String) -> bool:
    return validate(book).ok and book.active != null and book.active.session_id == session_id and book.active.round.id == round_id

static func checkpoint(book: Dictionary, session_id: String, round_id: String, round_value: Dictionary) -> Dictionary:
    if not _current(book, session_id, round_id) or book.active.state != "active" or not _round_valid(round_value) or round_value.id != round_id or round_value.stage != book.active.stage or round_value.phase < book.active.round.phase or round_value.state == "result": return _bad("Invalid or stale practice checkpoint")
    if book.active.round.state == "result": return _bad("Stopped round requires explicit next attempt")
    if round_value == book.active.round: return {"ok": true, "book": book.duplicate(true)}
    var response: Dictionary = _advance(book)
    if response.ok: response.book.active.round = round_value.duplicate(true)
    return response

static func record(book: Dictionary, session_id: String, round_id: String, phase: float) -> Dictionary:
    if not _current(book, session_id, round_id): return _bad("Stale practice result")
    var current: Dictionary = book.active
    if current.round.state == "result":
        if phase == current.round.phase: return {"ok": true, "book": book.duplicate(true)}
        return _bad("Changed practice result")
    if current.state != "active" or current.round.state not in ["running", "expired", "paused"] or not is_finite(phase) or phase < current.round.phase: return _bad("Practice round cannot stop")
    var outcome: Dictionary = evaluate(int(current.stage), phase)
    if not outcome.ok: return outcome
    outcome.erase("ok")
    outcome.round_id = round_id
    var response: Dictionary = _advance(book)
    if not response.ok: return response
    var active_value: Dictionary = response.book.active
    active_value.outcomes.append(outcome)
    active_value.round.phase = phase
    active_value.round.state = "result"
    active_value.round.anchored = false
    if active_value.outcomes.size() == SESSION_LENGTH:
        active_value.state = "complete"
        var summary_value: Dictionary = _summary(session_id, active_value.outcomes)
        var found := false
        for record_value in response.book.records:
            if record_value.stage != active_value.stage: continue
            found = true
            if record_value.sessions >= 1000000: return _bad("Practice session limit")
            record_value.sessions += 1
            record_value.history.append(summary_value.duplicate(true))
            if record_value.history.size() > 5: record_value.history.pop_front()
            if summary_value.hits > record_value.best.hits or (summary_value.hits == record_value.best.hits and summary_value.mean_abs_ms < record_value.best.mean_abs_ms): record_value.best = summary_value.duplicate(true)
            record_value.qualified = record_value.best.hits >= QUALIFY_HITS
        if not found:
            response.book.records.append({"stage": active_value.stage, "sessions": 1, "qualified": summary_value.hits >= QUALIFY_HITS, "best": summary_value.duplicate(true), "history": [summary_value.duplicate(true)]})
    if not validate(response.book).ok: return _bad("Invalid proposed practice result")
    return response

static func next_round(book: Dictionary, session_id: String, old_round_id: String, new_round_id: String) -> Dictionary:
    if not _current(book, session_id, old_round_id) or book.active.state != "active" or book.active.round.state != "result": return _bad("Next practice attempt unavailable")
    for outcome in book.active.outcomes:
        if outcome.round_id == new_round_id: return _bad("Practice attempt identity reused")
    var round_response: Dictionary = create_round(int(book.active.stage), new_round_id)
    if not round_response.ok: return round_response
    var response: Dictionary = _advance(book)
    if response.ok: response.book.active.round = round_response.round
    return response

static func abandon(book: Dictionary, session_id: String) -> Dictionary:
    if not validate(book).ok or book.active == null or book.active.session_id != session_id or book.active.state != "active": return _bad("No matching active session")
    var response: Dictionary = _advance(book)
    if response.ok: response.book.active.state = "abandoned"
    return response
