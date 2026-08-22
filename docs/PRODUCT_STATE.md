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
- App Store Connect app record: NOT YET CREATED

Apple requires the app record to exist before a TestFlight build can be uploaded. The supported App Store Connect API currently exposes app lookup/update but not creation of a new app record, so this one record must be created in the App Store Connect UI.

## TestFlight bridge

One More Floor contains `.github/workflows/99-9-testflight-bridge.yml` and keeps the existing App Store Connect API signing secrets. The bridge is prepared to:

1. Read the private `acciento89-bot/99-9` source.
2. Build with Godot 4.7.2 on macOS 26.
3. Export the iOS Xcode project.
4. Archive for iPhone/iPad.
5. Sign through Apple automatic/cloud signing using the existing ASC API key.
6. Upload v1.0.0 (1) to TestFlight.

The bridge deliberately does not publish private 99-9 source or build artifacts in the public One More Floor repository.

### Remaining release prerequisites

- Create the `99.9%` iOS app record in App Store Connect using bundle ID `de.kamilunavo.ninenine`.
- Add `NINENINE_REPO_TOKEN` to the One More Floor Actions secrets. It should be a fine-grained GitHub token with read-only Contents access to only the private `99-9` repository.

The existing ASC secrets were probed from the private 99-9 repository and are not inherited there, so the cross-repository read token is the intended bridge rather than duplicating Apple credentials.

The next milestone is the first real TestFlight upload and physical-device gameplay validation before monetization work begins.
