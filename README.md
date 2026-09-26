# Ten Second Heist

A native portrait iPhone planning puzzle for Rev Point Studios. Plan coordinated routes for a thief, hacker, and decoy without a time limit. Press **GO** to run a deterministic ten-second operation, inspect the timeline, rewind, change the plan, and try again. Replays and retries are free.

## Build

1. Open `TenSecondHeist.xcodeproj` in Xcode 16 or later. Deployment target: iOS 17.
2. Select the `TenSecondHeist` target, choose your Apple Developer team, and register or adjust the bundle ID `com.revpointstudios.tensecondheist` if needed. Keep the App Store Connect ID consistent.
3. Run the `TenSecondHeist` shared scheme on an iPhone simulator. Set **Edit Scheme → Run → Options → StoreKit Configuration** to `TenSecondHeist/Resources/Local.storekit` for *local simulated* purchase testing.
4. Run the `TenSecondHeistTests` test target. CI builds the simulator app and tests all authored references on macOS.

The project is generated deterministically by `python3 tools/create_xcodeproj.py`. Re-run that script if you add Swift source files. The checked-in `.xcodeproj` opens directly without an extra generator dependency.

## Content and play

`TenSecondHeist/Resources/levels.json` contains 48 authored levels in four locations; levels 1–8 are free. Each includes a stable ID, briefing, floor plan, risk, hint, objectives threshold, fixtures, and an unassisted reference plan. The authored source is `tools/build_levels.py`; use `python3 tools/build_levels.py && python3 tools/verify_levels.py` after editing. The XCTest suite independently executes all 48 references in the production Swift simulation.

Tap a crew chip, then drag across the floor plan. The game snaps the route to adjacent walkable tiles. Add WAIT, TAKE, HACK, or DISTRACT at the selected crew member’s current endpoint. Tap an action chip to remove that action and later ones; Undo Last removes one. Rewind to inspect the result; scrubbing shows a deterministic snapshot. Editing recalculates the entire simulation from time zero. Reset Plan asks for confirmation and offers Undo Reset.

See [gameplay rules](docs/GAMEPLAY.md), [Apple/TestFlight handoff](docs/TESTFLIGHT.md), [App Store copy draft](docs/APP_STORE.md), and [original asset record](docs/ASSETS.md).

## Purchases and data

StoreKit 2 product `com.revpointstudios.tensecondheist.campaign` permanently unlocks levels 9–48. The price shown in the app comes from StoreKit. Restore Purchases syncs that non-consumable entitlement.

Three introductory Inside Help tokens are issued once per local save and work offline. Optional 5-token and 12-token consumable packs use StoreKit and a private CloudKit wallet to sync paid credits and assistance unlocks across devices signed into the same iCloud account. An iCloud connection is required to buy or spend paid tokens. Paid credits are applied once per verified transaction, and each spend conditionally updates the wallet. Tips and camera loops stay unlocked for a level; switching assistance off allows an unassisted Perfect Heist. The three included tokens and other progress remain local and may be lost after a bare reinstall. Before enabling the packs in App Store Connect, configure the CloudKit container, deploy its schema to Production, and verify purchases, refunds, interruptions, simultaneous spends, and reinstall on signed devices.

Offline gameplay requires no account or backend. A local save does not survive an uninstall unless restored through the device's own backup. StoreKit restoration needs network access. No analytics, ads, subscriptions, or tracking are included.

## Current verification boundary

The Python verifier checks each authored reference against a mirrored rules implementation and checks map/fixture validity. The XCTest suite uses the actual Swift engine and covers reference solutions, determinism, camera timing, invalid routes, help duration, and save behavior. A macOS CI run is required for native compile and simulator test confirmation; physical device feel, audio interruptions, replay encoding, StoreKit sandbox and TestFlight purchases need hands-on checks. The local StoreKit file simulates a store and does not prove App Store Connect products work.
