# 99.9% Product State

## Current target

v1.0.0 Build 4 physical-device regression test.

## Core gameplay

- One-tap precision loop
- 99.900% streak threshold
- 100.000% perfect hit
- Increasing difficulty through streak speed
- Local best score / best streak persistence
- Portrait phone/tablet UI
- iOS + Android export presets

## Build 1 baseline

GitHub Actions run 32576070461 passed Godot parse/smoke, iOS/Xcode compile and Android APK export.

Build 1 was uploaded through the One More Floor TestFlight bridge and physically validated on a real iPhone on 2026-08-22.

Validated on-device:

- app launch: PASS
- portrait layout: PASS
- tap to start / stop: PASS
- result screen: PASS
- 99.900%+ streak threshold: PASS
- streak increment: PASS
- next-round flow: PASS
- local best persistence/display: PASS

Observed results included 99.929% and a near-perfect 99.993%.

## Build 2 feature milestone

Build 2 added:

- Main menu
- World leaderboard
- Local stats
- Settings/player name
- In-game pause/resume/restart/main-menu flow
- Persistent per-installation player UUID
- Supabase cross-platform leaderboard client
- Android internet permission

Physical-device review found the iOS player-name field visible but not editable/focusable. The menu was also considered too prototype-like.

## Build 3 UI / customization milestone

PR #3 was squash-merged as `dfe18657c2e6ae863366bdf00bcfd55ef83cd354` after GitHub Actions run 32580003697 passed:

- Godot 4.7.2 parse + main-scene smoke: PASS
- live Supabase leaderboard endpoint: PASS
- iOS Godot export + Xcode generic-device compile: PASS
- Android debug APK export: PASS

Build 3 added:

- redesigned main menu with clearer hierarchy and personal-record card
- redesigned settings, stats, leaderboard and pause surfaces
- hardened mobile player-name input with editable/focus/touch/virtual-keyboard handling
- Designs screen
- free MIDNIGHT design
- premium preview designs: NEON PULSE, GOLD RUSH, AURORA
- persistent theme selection / ownership shell

Build 3 physical-device findings:

- redesigned menu/settings/theme surfaces render: PASS
- player-name field opens keyboard and can be edited/saved: PASS
- premium theme preview flow works visually: PASS
- core PLAY flow regression discovered: after entering the game, gameplay taps could be swallowed by the full-screen UI Control before reaching `_unhandled_input`: FAIL
- flat/dark background still felt too empty and was rejected for final polish

This blocked StoreKit/paid-theme wiring until core gameplay was restored.

## Build 4 gameplay-input + background milestone

PR #4 was squash-merged as `b35be682c765b7e559e5a8f6ffd84c51b3e80c12` after GitHub Actions run 32581337356 passed all release gates:

- Godot 4.7.2 parse + main-scene smoke: PASS
- live Supabase leaderboard endpoint: PASS
- iOS Godot export + Xcode generic-device compile: PASS
- Android debug APK export: PASS

A first CI attempt correctly failed on a GDScript float-inference parser error in the new atmosphere renderer. The variable was explicitly typed and the complete gate was rerun green before merge.

Build 4 changes:

- new `scripts/main_v4.gd` inherits the validated Build 3 controller
- gameplay taps moved from `_unhandled_input` to the gameplay Control's direct `gui_input`
- explicit pause-button touch guard prevents pause taps from counting as gameplay taps
- PLAY -> READY -> RUNNING -> RESULT -> NEXT ROUND remains the existing game-state flow
- flat black backdrop replaced with animated theme-aware atmosphere
- shared moving glow clouds, color wash and subtle dust/stars
- MIDNIGHT: orbital rings / night-sky treatment
- NEON PULSE: drifting neon grid
- GOLD RUSH: animated gold light rays
- AURORA: animated flowing ribbons
- game background is subdued relative to menu backgrounds so the precision meter stays readable

Build 4 was uploaded successfully to TestFlight through One More Floor bridge run 32581479782 with explicit build number 4. Private-source checkout, Godot export, Xcode archive, automatic/cloud signing and TestFlight upload all passed.

### Build 4 physical-device checklist

Validate on iPhone before any IAP work continues:

- app/menu launch
- PLAY NOW enters game
- first game tap starts the moving meter
- second game tap stops the meter and produces a result
- result tap advances to next round
- pause tap pauses but never starts/stops a round
- resume continues normally
- restart run works
- return to menu works
- MIDNIGHT animated background looks good and is not just black
- NEON/GOLD/AURORA previews show distinct animated background treatments
- player-name editing still works
- leaderboard/stats still work

## Global leaderboard backend

Supabase project `bqctetqraszsvknczjjr` hosts isolated 99.9% resources under `ninenine_*`.

Created:

- `public.ninenine_players`
- `public.ninenine_score_events`
- `public.ninenine_leaderboard_hit`
- `public.ninenine_leaderboard_streak`
- RPC `ninenine_submit_score`
- RPC `ninenine_set_name`
- Edge Function `ninenine-leaderboard`

Security/design:

- RLS enabled
- direct anon/authenticated table writes revoked
- direct client RPC execution revoked
- Edge Function uses service-role access internally
- streak is calculated server-side from submitted round scores
- 300 ms minimum submission interval
- score constrained to 0..100000 milli-percent
- score-event history retained for audit/debugging
- gameplay never blocks on leaderboard networking failure

Global ranking modes:

1. BEST HIT — best percentage descending, then best streak, then perfect-count tie-break
2. LONGEST STREAK — best streak descending, then best percentage, then perfect-count tie-break

The leaderboard is shared across iOS and Android.

Backend validation:

- transactional database smoke: PASS
- player-name RPC write: PASS
- 99.950% score submission: PASS
- server-calculated streak=1: PASS
- best-hit/game-count update: PASS
- live Edge Function HTTP client path: PASS (HTTP 200)

## Apple / TestFlight

- Team: TKG684N5GL
- Bundle ID: de.kamilunavo.ninenine
- Apple internal App ID name: Nine Nine
- App Store version: 1.0.0
- Build 1: physically validated baseline
- Build 2: player-name input regression found
- Build 3: player-name fix/UI/theme pass; gameplay-input regression found
- Build 4: uploaded successfully; awaiting physical-device validation

## Monetization state

Still intentionally not live:

- Ads / AdMob
- Consent / ATT
- Analytics
- StoreKit / Google Play Billing
- paid-theme entitlements
- cloud saves

Premium design product IDs reserved for the next pass after Build 4 device validation:

- `de.kamilunavo.ninenine.theme.neon`
- `de.kamilunavo.ninenine.theme.gold`
- `de.kamilunavo.ninenine.theme.aurora`

Target product type: non-consumable / permanent unlock. Restore/entitlement handling is required before paid themes can ship.
