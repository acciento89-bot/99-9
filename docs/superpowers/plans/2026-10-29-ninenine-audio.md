# NineNine original audio implementation plan

> Execution: inline, owner-authorized without routine confirmation. Root performs independent source review before cloud/native work.

**Goal:** supply original quiet music/effects and persistent Settings controls while preserving timing, data, providers, and Android-first scope.

**Architecture:** deterministic checked-in WAVs; a single scene child owns audio/preferences; a new subclass of the existing active practice UI adds only audio/layout/focus hooks.

**Tech:** Python standard library, Godot 4.7.2 GDScript, ConfigFile, AudioStreamWAV/AudioStreamPlayer.

**Spec:** `docs/superpowers/specs/2026-10-29-ninenine-audio-design.md`.

**Constraints:** existing project is an isolated feature branch at d2790fd; no push, native export, Editor, provider, device, credentials, or iOS changes. Preserve prior evidence and any human dirt. No new dependencies or sample/plugin audio.

## Tasks

1. Write PCM and real headless service/UI tests first. Observe missing generator/service failure (RED). Implement deterministic WAVs, notices/provenance and bounded service. Run generator/service tests (GREEN).
2. Exercise Settings toggles, cold persistence, failed writes, focus/classic/practice hold and actual new-result callbacks. Observe missing active integration (RED); add subclass and scene binding. Run isolated headless tests without Editor/import and existing pure model/archive suites (GREEN).
3. Update only Android preset and selected Android source/sign version pins to 8. Retain live max 6 and document unpublished 7 supersession; tests reject both stale 7 and invalid codes. Preserve exact iOS/project hashes.
4. Run CPU/headless suites, generator reproducibility, diff/asset/hash review. Commit scoped files with `[skip ci]`; save honest source-only receipt and future cloud graph. Root reviews before cloud build.

## Review focus

No unbounded runtime generator, duplicate music owner, audible abrupt loop boundary, hidden preference-save error, incorrect post-background timing/resume, provider/game-state alteration, false live version, lost export WAV/notice, or effects on failed/repeated practice saves. Hearing/Android lifecycle/package proof remains pending genuine later native QA.

## Execution ledger

- Existing isolated feature branch and clean d2790fd baseline verified; no new worktree required because Root expressly selected this source directory.
- Initial RED: missing generator/raw export entries and missing active audio subclass. Version RED: original code-7 predicate accepts stale 7; no unpublished reservation exists. Caption RED: the real iOS menu/ranking show cross-platform strings.
- Ruling: retain saved live maximum 6 and reserve the unpublished code 7 explicitly, then select 8. This preserves provider history; a fresh live check is still needed before delivery.
- Ruling: no local Editor/import. The isolated UI fixture changes only font loading to raw `FontFile` with the original TTF; full native/imported asset validation remains pending. WAV exported remapping is tested separately with an actual temporary resource remap.
- Ruling: Godot's inherited `_notification` dispatch is automatic. A new exact-count test failed with the redundant super call and passes after removing it; Practice/model/archive algorithms remain unchanged.
- Root's additional explicit request: iOS-neutral captions, Android wording preserved. The actual two UI paths failed before formatter binding and pass after it; no Apple build or policy result is claimed.
- Targeted author self-review and CPU/headless verification precede commit. Root-assigned independent review remains the gate before cloud/native execution.
