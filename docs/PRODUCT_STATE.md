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

## Mobile validation

GitHub Actions run 32576070461 passed all three initial gates:

- Godot 4.7.2 project parse + main-scene smoke test: PASS
- iOS Godot export + unsigned Xcode generic-device compile on macOS 26: PASS
- Android debug APK export: PASS

PR #1 was squash-merged after the green validation run.

## Apple

- Team: TKG684N5GL
- Bundle ID: de.kamilunavo.ninenine
- Apple internal App ID name: Nine Nine
- App Store version: 1.0.0
- Build: 1
- Bundle ID registration: COMPLETE via One More Floor App Store Connect bridge
- App Store Connect app record: COMPLETE

## TestFlight

One More Floor hosts the TestFlight bridge and keeps the existing App Store Connect API signing secrets. `NINENINE_REPO_TOKEN` provides read-only access to the private `acciento89-bot/99-9` source.

TestFlight bridge run 32577023811 completed successfully:

1. Private 99-9 checkout: PASS
2. App Store Connect app lookup: PASS
3. Godot 4.7.2 macOS + iOS template setup: PASS
4. Godot iOS Xcode export: PASS
5. Xcode scheme resolution: PASS
6. Release archive creation: PASS
7. Apple automatic/cloud signing + TestFlight upload: PASS

The upload of v1.0.0 (1) was accepted successfully by Apple's upload tooling.

Two immediate App Store Connect API checks after the successful upload did not list Build 1 yet (`NOT_VISIBLE_YET`). This means the upload has completed but Apple's server-side processing/listing has not yet surfaced the build in the Builds API at the time of the checkpoint.

No second upload should be started while Build 1 is still being processed, to avoid an unnecessary build-number bump or duplicate-release attempt.

The next milestone is physical-device gameplay validation of Build 1 in TestFlight. Monetization work stays intentionally blocked until that playtest passes.
