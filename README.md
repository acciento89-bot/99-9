# 99.9%

One-tap precision game by Kamilunavo Games, built with Godot 4.7.x for iOS and Android.

## v1.0.0 playtest scope

- Tap once to start the meter.
- Tap again to stop it.
- 99.900% or better keeps the streak alive.
- 100.000% is the perfect hit.
- Best score, best streak and played rounds are stored locally.
- Meter speed rises with the streak.
- No ads, tracking, analytics, login or network dependency in this playtest build.

## Mobile identifiers

- iOS bundle ID: `de.kamilunavo.ninenine`
- Android application ID: `de.kamilunavo.ninenine`
- Marketing version: `1.0.0`
- Build/version code: `1`

## Build targets

`export_presets.cfg` contains:

- `iOS Playtest` — iPhone + iPad, arm64, Xcode-project export
- `Android Playtest` — APK playtest export for arm64-v8a + armeabi-v7a

GitHub Actions validates the project and builds test artifacts before TestFlight distribution is enabled.
