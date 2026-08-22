# 99.9% Product State

## Current target

v1.0.0 (1) mobile playtest.

## Included

- Core one-tap precision loop
- 99.900% streak threshold
- 100.000% perfect hit
- Increasing difficulty through streak speed
- Local best score / best streak persistence
- Portrait phone/tablet UI
- iOS + Android export presets
- Basic app icon

## Intentionally excluded from first device test

- Ads
- Consent / ATT
- Analytics
- Leaderboards
- Cloud saves
- In-app purchases

## Apple

- Team: TKG684N5GL
- Bundle ID: de.kamilunavo.ninenine
- App Store version: 1.0.0
- Build: 1

## Validation

GitHub Actions is the release gate for the first device build: Godot parse/smoke test, unsigned iOS compile, and Android debug APK export must pass before TestFlight upload.

A dedicated pull request validation run is used to expose all workflow job results before the TestFlight bridge is enabled.

The first milestone is a clean device/TestFlight validation before monetization work begins.
