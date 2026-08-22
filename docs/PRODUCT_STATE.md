# 99.9% Product State

## Current target

v1.0.0 Build 2 physical-device playtest.

## Core gameplay

- One-tap precision loop
- 99.900% streak threshold
- 100.000% perfect hit
- Increasing difficulty through streak speed
- Local best score / best streak persistence
- Portrait phone/tablet UI
- iOS + Android export presets

## Build 1 baseline

GitHub Actions run 32576070461 passed:

- Godot 4.7.2 project parse + main-scene smoke test: PASS
- iOS Godot export + unsigned Xcode generic-device compile on macOS 26: PASS
- Android debug APK export: PASS

Build 1 was uploaded through the One More Floor TestFlight bridge and physically validated on a real iPhone on 2026-08-22.

Validated on-device:

- App launch: PASS
- Portrait layout: PASS
- Tap to start / stop: PASS
- Result screen: PASS
- 99.900%+ streak threshold: PASS
- Streak increment: PASS
- Next-round flow: PASS
- Local best persistence/display: PASS

Observed results included 99.929% and a near-perfect 99.993%.

## Build 2 feature milestone

PR #2 was squash-merged to main after GitHub Actions run 32578200206 passed all platform gates:

- Godot parse + main-scene smoke: PASS
- iOS Xcode device compile: PASS
- Android debug APK export: PASS

Build 2 adds:

- Main menu: PLAY / WORLD LEADERBOARD / STATS / SETTINGS
- In-game PAUSE button
- Pause actions: RESUME / RESTART RUN / MAIN MENU
- Gameplay tap handling moved to `_unhandled_input` so menu/pause button taps cannot accidentally stop a round
- Persistent random per-installation player UUID
- Editable worldwide leaderboard display name
- Local stats screen
- Android internet permission

## Global leaderboard backend

Supabase project `bqctetqraszsvknczjjr` hosts a fully isolated 99.9% backend using only `ninenine_*` resources.

Created:

- `public.ninenine_players`
- `public.ninenine_score_events`
- `public.ninenine_leaderboard_hit`
- `public.ninenine_leaderboard_streak`
- RPC `ninenine_submit_score`
- RPC `ninenine_set_name`
- Edge Function `ninenine-leaderboard`

Security/design:

- RLS enabled on both tables
- direct anon/authenticated table access revoked
- direct client RPC execution revoked
- Edge Function uses service-role access internally
- leaderboard RPC streak is calculated server-side from submitted round scores; client cannot submit an arbitrary streak value
- 300 ms server-side minimum submission interval
- score range constrained to 0..100000 milli-percent
- score-event history retained for audit/debugging
- gameplay never blocks if leaderboard networking fails

Global ranking modes:

1. BEST HIT — best percentage descending, then best streak, then perfect-count tie-break
2. LONGEST STREAK — best streak descending, then best percentage, then perfect-count tie-break

The leaderboard is shared across iOS and Android.

Validation:

- transactional database smoke: PASS
- player-name write: PASS
- 99.950% score submission: PASS
- server-calculated streak=1: PASS
- best-hit/game-count update: PASS
- live Edge Function HTTP client path: PASS (HTTP 200)

The live HTTP gate is part of the mobile build workflow so a deploy with a broken leaderboard endpoint cannot be treated as release-ready.

## Apple / TestFlight

- Team: TKG684N5GL
- Bundle ID: de.kamilunavo.ninenine
- Apple internal App ID name: Nine Nine
- App Store version: 1.0.0
- Build 1: physically validated
- Build 2: uploaded successfully via One More Floor bridge run 32578442242

Build 2 passed private-source checkout, Godot 4.7.2 iOS export, Xcode release archive, Apple automatic/cloud signing and TestFlight upload.

Immediate App Store Connect API checks after the accepted upload returned `NOT_VISIBLE_YET`, meaning Apple has accepted the upload but has not surfaced Build 2 in the Builds API yet. Do not upload another build while Build 2 is processing.

One More Floor retains the App Store Connect API signing secrets and `NINENINE_REPO_TOKEN` provides read-only access to the private `acciento89-bot/99-9` source for the TestFlight bridge.

## Still intentionally excluded

- Ads / AdMob
- Consent / ATT
- Analytics
- Cloud saves
- In-app purchases

## Next milestone

When Build 2 appears in TestFlight, physically validate:

- main-menu navigation
- pause while the meter is moving
- resume without meter jump/regression
- restart run
- return to main menu
- settings player-name save
- complete at least one round to enter the global ranking
- worldwide Best Hit leaderboard load
- worldwide Longest Streak leaderboard load
- own rank/display name
- no accidental gameplay stop from UI button taps

Monetization remains blocked until Build 2 passes this device regression.
