# Build 5 StoreKit device-failure fix

Observed on physical iPhone / TestFlight Build 5:

- Premium design previews work.
- Premium prices do not appear.
- UI remains on the store-loading path.

Root causes identified on 2026-08-22:

1. `scripts/iap_service.gd` created a second instance of `godot_iap.gd` even though the enabled GodotIap editor plugin already installs `/root/GodotIapPlugin` as an autoload. The wrapper uses a static initialization guard, so the duplicate instance can remain without the native StoreKit plugin.
2. Live App Store Connect diagnostic run `32586373321` found all three non-consumables in `MISSING_METADATA` state. Price schedules and worldwide availability exist, but the IAPs are not yet review-ready.

Fix in this branch:

- reuse `/root/GodotIapPlugin`
- wait for node readiness before native calls
- retain a defensive fallback only when the autoload is missing
- distinguish native connection failure from a connected store returning zero products
- keep purchase / restore behavior unchanged

Apple catalog still requires completion of missing review metadata before the premium products can become available in TestFlight/Sandbox.
