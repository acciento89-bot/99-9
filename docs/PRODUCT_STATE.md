# 99.9% Product State

## Current target

v1.0.0 Build 5 premium purchase / restore physical-device test in TestFlight.

Build 5 has been uploaded successfully to App Store Connect and may still be processing before it becomes installable in TestFlight.

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

Physical-device visual feedback on Build 4: the atmosphere still reads too much like moving circles/glow geometry and is not considered final premium-quality artwork. A dedicated visual overhaul remains planned after the Build 5 IAP validation.

## Build 5 premium IAP milestone

PR #5 was squash-merged as `cda0ae2290ecd12e08917d0fc71ee442ce00b905` after GitHub Actions run 32585228289 passed the complete premium release gate:

- Godot 4.7.2 parse + main-scene smoke: PASS
- live Supabase leaderboard endpoint: PASS
- iOS Godot export + Xcode generic-device compile: PASS
- `GodotIap.framework` presence/embed verification: PASS
- Android Gradle debug APK export: PASS
- Android APK native IAP/Billing payload verification: PASS

Build 5 adds:

- official OpenIAP / GodotIap 3.0.2 vendored into the project
- StoreKit 2 purchase path on iOS
- Google Play Billing integration path on Android
- localized store prices in the Designs screen
- permanent non-consumable theme purchases
- Restore Purchases flow
- entitlement refresh on store connection
- local theme ownership cache rebuilt from store entitlements
- purchase completion equips the newly unlocked theme
- iOS deployment minimum 17.0 as required by the current plugin integration
- Android Gradle export with minSdk 24

Apple premium products are created and configured in App Store Connect:

- `de.kamilunavo.ninenine.theme.neon` — Neon Pulse
- `de.kamilunavo.ninenine.theme.gold` — Gold Rush
- `de.kamilunavo.ninenine.theme.aurora` — Aurora

Apple product configuration:

- product type: non-consumable / permanent unlock
- Germany base price: EUR 0.99 each
- worldwide availability: configured
- German metadata: configured
- English metadata: configured

The TestFlight bridge was hardened for IAP before distribution. Bridge run 32585489179 verified the framework in the generated Xcode project and again inside the release archive, then successfully uploaded `1.0.0 (5)` to App Store Connect/TestFlight.

### Build 5 physical-device checklist

Do not call paid themes production-ready until these are tested on a real iPhone through TestFlight:

- app launches normally
- PLAY / stop / result / next-round regression still works
- pause / resume / restart / return-to-menu still works
- Designs screen opens normally
- store connects and real localized prices appear
- Neon Pulse purchase opens Apple's sandbox/TestFlight purchase sheet
- successful purchase unlocks and equips Neon Pulse
- purchased theme remains available after app restart
- Restore Purchases completes without error
- restore rehydrates a previously owned premium theme after local ownership is cleared/reinstall scenario
- canceling a purchase does not unlock a theme
- leaderboard, stats and player-name editing still work

One successful product purchase is enough to validate the general Apple purchase path. Additional products should at least be checked for correct localized price/product mapping; they do not all need to be purchased unless a mapping issue appears.

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
- Build 4: gameplay-input fix/background pass uploaded; background visual quality still rejected as final
- Build 5: premium StoreKit 2 purchase/restore build uploaded successfully; physical IAP validation pending

## Monetization state

Implemented / in TestFlight Build 5:

- Apple StoreKit 2 integration through GodotIap/OpenIAP
- Apple permanent paid-theme product catalog
- localized store price display
- purchase flow
- restore flow
- entitlement refresh / local ownership cache

Implemented in code/build validation but not yet commercially configured on Google Play:

- Google Play Billing native integration path
- Android Billing payload packaged in the APK

Still intentionally not live:

- Ads / AdMob
- Consent / ATT
- Analytics
- Google Play paid-theme product catalog
- cloud saves

Paid themes must remain cosmetic only; leaderboard/gameplay advantage must never depend on purchasing a theme.

## Planned next passes

### Visual premium overhaul

Replace the current glow/circle-heavy atmosphere with clearly recognizable theme identities:

- MIDNIGHT — deep starfield / constellation / orbital-night scene rather than generic circles
- NEON PULSE — synthwave/cyber horizon, perspective lanes and controlled neon motion
- GOLD RUSH — dark obsidian architecture, metallic gold shards/veins and premium light sweeps
- AURORA — layered polar-light curtains with depth and atmospheric stars

Do not upload the visual-overhaul build to TestFlight until Build 5 purchase/restore regression is physically checked.

### Retention / social candidates

1. Daily Perfect — one globally identical seeded challenge per day, exactly three attempts, daily ranking.
2. Challenges / Duels — share a result challenge; recipient gets the same meter-speed setup and a limited number of attempts to beat it.

Both features must preserve the core one-tap game and remain skill-based rather than pay-to-win.
