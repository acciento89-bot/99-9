# 99.9% Product State

## Current target

v1.0.0 Build 3 physical-device playtest.

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

PR #2 was squash-merged to main after GitHub Actions run 32578200206 passed all platform gates.

Build 2 added:

- Main menu
- World leaderboard
- Local stats
- Settings/player name
- In-game pause/resume/restart/main-menu flow
- Persistent per-installation player UUID
- Supabase cross-platform leaderboard client
- Android internet permission

Physical-device review of Build 2 confirmed the new menu/stats/leaderboard screens render and navigate, but exposed one real iOS usability regression:

- Player-name LineEdit is visible but tapping it does not enter editable/focused keyboard state: FAIL

The Build 2 menu was also judged functional but too prototype-like, so monetization stayed blocked pending a UI polish pass.

## Build 3 UI / customization milestone

PR #3 was squash-merged to main as commit `dfe18657c2e6ae863366bdf00bcfd55ef83cd354` after GitHub Actions run 32580003697 passed all four gates:

- Godot 4.7.2 parse + main-scene smoke: PASS
- live Supabase leaderboard endpoint: PASS
- iOS Godot export + Xcode generic-device compile: PASS
- Android debug APK export: PASS

Build 3 replaces the procedural UI controller with `scripts/main_v3.gd` and adds:

- redesigned main menu with clearer visual hierarchy and a dedicated personal-record card
- redesigned settings, stats, leaderboard and pause surfaces
- explicit mobile player-name input hardening:
  - `editable=true`
  - `focus_mode=FOCUS_ALL`
  - `mouse_filter=STOP`
  - `virtual_keyboard_enabled=true`
  - select-all-on-focus
  - caret blink
  - explicit touch GUI handler calling `grab_focus()`
  - visible focused border/caret styling
  - submit-on-keyboard action plus Save Player Name button
- Designs screen
- persistent theme selection and ownership structure
- free MIDNIGHT design
- premium preview designs:
  - NEON PULSE
  - GOLD RUSH
  - AURORA
- premium designs can be previewed across the app but cannot be equipped unless owned
- premium purchase UI is intentionally locked until StoreKit/Google Play Billing wiring is added
- themes recolor app background, glow, cards, buttons, input field and gameplay meter

## Global leaderboard backend

Supabase project `bqctetqraszsvknczjjr` hosts isolated 99.9% resources using the `ninenine_*` namespace.

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

Validation:

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
- Build 1: physically validated
- Build 2: physically reviewed; player-name input regression found
- Build 3: uploaded successfully through One More Floor TestFlight bridge run 32580145642

Build 3 passed private-source checkout, requested build-number resolution to 3, Godot 4.7.2 iOS export, Xcode release archive, Apple automatic/cloud signing and TestFlight upload.

## Monetization state

Still intentionally not live:

- Ads / AdMob
- Consent / ATT
- Analytics
- StoreKit / Google Play Billing
- paid-theme entitlements
- cloud saves

The visual/ownership shell for paid designs now exists. Premium themes must use platform IAP before they can be sold or permanently equipped.

## Build 3 physical-device checklist

When Build 3 appears in TestFlight, validate on iPhone:

- redesigned main menu renders correctly
- PLAY / WORLD RANKING / MY STATS / DESIGNS / SETTINGS navigation
- tap Player Name field -> keyboard opens and field becomes editable
- type a different name and save it
- saved name persists after leaving/reopening settings
- saved name appears in stats and global ranking after score sync
- MIDNIGHT equips normally
- NEON PULSE preview changes the app look
- GOLD RUSH preview changes the app look
- AURORA preview changes the app look
- leaving Designs reverts locked preview to the owned/equipped theme
- premium themes cannot be permanently equipped yet
- pause/resume/restart/gameplay still work
- no UI tap accidentally triggers gameplay

Only after this device pass should StoreKit/Google Play Billing products for premium designs be wired.
