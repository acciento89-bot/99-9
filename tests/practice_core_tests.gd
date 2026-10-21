extends SceneTree
const Practice = preload("res://practice_model.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("FAIL " + message)
func good(response: Dictionary, message: String) -> Dictionary:
    check(bool(response.get("ok", false)), message)
    return response
func _initialize() -> void:
    var definitions: Array = Practice.catalog()
    check(definitions.size() == 8, "eight distinct target/direction stages")
    check(definitions[0].target == 75.0 and definitions[0].direction == "rising", "first target uses actual cosine crossing")
    check(definitions[1].direction == "falling" and definitions[7].target == 100.0, "both directions and original peak")
    var rising: Dictionary = Practice.evaluate(1, TAU / 3.0)
    var falling: Dictionary = Practice.evaluate(2, TAU * 2.0 / 3.0)
    check(rising.ok and rising.hit and absf(rising.signed_ms) < .000001, "rising75 exact phase")
    check(falling.ok and falling.hit and absf(falling.signed_ms) < .000001, "falling75 exact phase")
    check(not Practice.evaluate(1, TAU * 2.0 / 3.0).hit, "same value wrong direction cannot qualify")
    check(Practice.evaluate(1, TAU / 3.0 - .02).signed_ms < 0 and Practice.evaluate(1, TAU / 3.0 + .02).signed_ms > 0, "specified first crossing yields signed early/late error")
    var edge_phase := acos(1.0 - (100.0 - .005) / 50.0)
    check(Practice.evaluate(8, edge_phase).hit and Practice.evaluate(8, PI).hit, "peak raw classic perfect boundary inclusive")
    check(not Practice.evaluate(8, acos(1.0 - (100.0 - .0051) / 50.0)).hit, "display rounding cannot grant peak hit")
    check(not Practice.evaluate(1, NAN).ok and not Practice.evaluate(99, PI).ok, "nonfinite and unknown stage rejected")
    var round: Dictionary = good(Practice.create_round(1, "round-a"), "round creation").round
    round = good(Practice.start_round(round), "explicit start").round
    round = good(Practice.tick(round, 99.0, true), "first frame reanchor").round
    check(round.phase == 0.0, "long startup frame excluded")
    round = Practice.tick(round, .25, true).round
    check(absf(round.phase - .3) < .000001, "actual fixed practice speed")
    round = Practice.tick(round, 999.0, false).round
    check(round.state == "paused" and absf(round.phase - .3) < .000001, "background pauses and preserves held phase")
    round = Practice.tick(round, 999.0, true).round
    check(round.state == "paused" and absf(round.phase - .3) < .000001, "foreground alone cannot silently resume")
    round = Practice.resume_round(round).round
    round = Practice.tick(round, 999.0, true).round
    check(absf(round.phase - .3) < .000001, "first explicit resume frame excluded")
    check(not Practice.tick(round, -1.0, true).ok and not Practice.tick(round, INF, true).ok, "invalid clock cannot poison state")
    round = Practice.tick(round, 10.0, true).round
    check(round.phase == TAU and round.state == "expired", "one cycle expires rather than silently wrapping")
    var slow: Dictionary = Practice.start_round(Practice.create_round(3, "frame-a").round).round
    var split: Dictionary = Practice.start_round(Practice.create_round(3, "frame-b").round).round
    slow = Practice.tick(slow, 0.0, true).round
    split = Practice.tick(split, 0.0, true).round
    slow = Practice.tick(slow, .2, true).round
    for i in range(20): split = Practice.tick(split, .01, true).round
    check(absf(slow.phase - split.phase) < .000001, "timing independent of frame subdivision")
    var original: Dictionary = Practice.empty_book()
    var book: Dictionary = good(Practice.begin(original, 1, "session-a", "attempt-0"), "first unlocked practice session").book
    check(original.active == null, "begin never mutates prior archive")
    check(not Practice.begin(original, 2, "locked", "attempt-x").ok, "ladder cannot skip qualification")
    for i in range(12):
        var rid := "attempt-%d" % i
        var started: Dictionary = Practice.start_round(book.active.round).round
        book = good(Practice.checkpoint(book, "session-a", rid, started), "active round checkpoint").book
        var before: Dictionary = book.duplicate(true)
        book = good(Practice.record(book, "session-a", rid, TAU / 3.0), "accepted actual stop").book
        check(before.active.outcomes.size() == i, "stop preserves previous snapshot")
        var retry: Dictionary = Practice.record(book, "session-a", rid, TAU / 3.0)
        check(retry.ok and retry.book.revision == book.revision, "exact callback retry cannot duplicate progress")
        check(not Practice.record(book, "session-a", rid, PI).ok, "changed terminal result rejected")
        if i < 11:
            book = good(Practice.next_round(book, "session-a", rid, "attempt-%d" % (i + 1)), "advance explicitly").book
            check(not Practice.record(book, "session-a", rid, TAU / 3.0).ok, "old round callback stale after next")
    check(book.active.state == "complete" and book.active.outcomes.size() == 12, "exact twelve actual outcomes")
    check(Practice.unlocked(book, 2) and not Practice.unlocked(book, 3), "qualification opens exactly next stage")
    check(book.records[0].best.hits == 12 and book.records[0].sessions == 1, "separate factual practice session best")
    var corrupted: Dictionary = book.duplicate(true)
    corrupted.schema = 99
    check(not Practice.validate(corrupted).ok, "future schema blocks mutation")
    corrupted = book.duplicate(true)
    corrupted.active.outcomes[0].signed_ms = NAN
    check(not Practice.validate(corrupted).ok, "damaged outcome cannot normalize into success")
    check(not book.has("best_value") and not book.has("best_streak") and not book.has("games_played"), "practice archive independent of classic scores")
    if failures == 0: print("NN PRACTICE CORE PASS checks=", checks)
    quit(0 if failures == 0 else 1)
