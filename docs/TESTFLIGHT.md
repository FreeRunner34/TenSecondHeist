# Apple Developer and TestFlight handoff

## Xcode and device checks

1. Open `TenSecondHeist.xcodeproj`; select your team and verify the bundle identifier `com.revpointstudios.tensecondheist` is available on your account. Keep iPhone-only and portrait settings unless you deliberately extend the UI.
2. Run the scheme on a small iPhone simulator and a current larger iPhone. Run all XCTest cases. Test route dragging near corners, role selection where paths overlap, scroll/timeline controls, Reset Plan and Undo Reset, backgrounding during playback and replay export, reduced motion, music/effects settings, and VoiceOver labels. Fix anything awkward before archive.
3. Test on a physical iPhone: start and complete levels including #5 and #48, fail deliberately and jump to the timestamp, scrub/rewind and retry, switch assistance off for Perfect Heist, sound interruptions, and video export/preview/share. Video is rendered only from the simulated game board; it never records device screens.
4. In **Edit Scheme → Run → Options**, choose `Local.storekit`; purchase, cancel, simulate pending, refund/revoke, restore, and relaunch. This is local StoreKit simulation only. Remove the local configuration from the launch scheme when testing real sandbox products or TestFlight.

## App Store Connect

1. Create a new free iOS app record matching the final bundle identifier. Choose a display name, primary category (Games / Puzzle), age rating, regions, availability, and screenshots. The app is free to download; **Full Campaign** is the paid permanent unlock.
2. Add a **non-consumable** IAP whose exact product ID is `com.revpointstudios.tensecondheist.campaign`; set your desired U.S. price point (proposed $1.99), localizations, review screenshot, availability, and review notes. Prices displayed inside the app come from StoreKit. Include the first IAP with the first app version when you eventually submit to App Review.
3. Do **not** enable `com.revpointstudios.tensecondheist.help5` or `com.revpointstudios.tensecondheist.help12` for sale. Their proposed prices are $0.99 and $1.99 respectively. Paid tokens require an atomic server or equivalent reliable cross-device ledger and conflict/reinstall recovery, followed by transaction and interruption testing. The three included local tokens remain playable, but are not recoverable after a bare reinstall.
4. Enable a public support page and privacy URL. Drafts are at `docs/index.html` and `docs/privacy.html`. If hosting them with GitHub Pages, enable Pages for this repository's `/docs` directory and confirm `https://freerunner34.github.io/TenSecondHeist/` and `/privacy.html` actually load before using those URLs in App Store Connect. The repository alone does not activate Pages.
5. Add metadata and fresh screenshots from the final build. Example subtitle: “Plan the perfect 10-second escape.” Explain the free eight levels, the permanent 40-level purchase, optional assistance, and unlimited free retries. Do not mention token packs as available.
6. Archive a Release build with your Apple Developer signing team, upload to App Store Connect, wait for processing, then enable internal TestFlight testing. Use an App Store Connect sandbox tester or TestFlight to test real product retrieval, buy/cancel/pending/revoke, campaign restoration on a second device, and offline entitlement behavior. External TestFlight testing may require Apple's beta review. A successful signed build and hands-on checks are required before calling it TestFlight-ready.

No upload, public app release, or App Review submission is performed by this repository.
