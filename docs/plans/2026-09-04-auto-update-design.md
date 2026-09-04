# Auto-update design

Date: 2026-09-04

## Goal

Users on a Sparkle-enabled build get new releases through the app, with an
"Install and Relaunch" flow, instead of downloading a DMG by hand.

## Decision

Sparkle 2 (2.9.x) via Swift Package Manager. Alternatives considered:

- Notify-and-link with the GitHub Releases API: no dependency, but a sandboxed
  app cannot replace itself in /Applications, so the user still drags the app.
- Mac App Store: changes distribution, review, and the Apple Events story.

## In the app

- `AppDelegate` owns one `SPUStandardUpdaterController`, started at launch.
- Status menu gains "Check for Updates…" below Settings.
- Info.plist: `SUFeedURL` pointing at `appcast.xml` on `main` via
  raw.githubusercontent.com, `SUPublicEDKey`, and
  `SUEnableInstallerLauncherService = YES` (required in the sandbox).
  `SUEnableAutomaticChecks = YES` so a windowless agent app does not show
  Sparkle's second-launch permission prompt. Installs are never silent:
  `SUAutomaticallyUpdate` stays at its default of NO.
- Entitlements: `com.apple.security.temporary-exception.mach-lookup.global-name`
  with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki`. No downloader XPC
  service; the app already has `com.apple.security.network.client`.
- README and the privacy paragraph say the app contacts GitHub once a day for
  updates and sends no system profile.

## Release flow

- One-time: `generate_keys` stores the private EdDSA key in the login Keychain
  and prints the public key for Info.plist. Export a backup with
  `generate_keys -x`. Losing the key means users must reinstall by hand once.
- `Tools/release.sh`, after stapling: copy the repo's `appcast.xml` next to the
  DMG, run `generate_appcast` with `--download-url-prefix` pointing at the
  GitHub release for that version and `--link` at the product page, then copy
  the result back to the repo root. The appcast is committed with the version
  bump.
- 1.2 is the first Sparkle-enabled release. 1.0 and 1.1 users install it by
  hand; later versions arrive through the app.

## Verification

- Unit tests: feed URL and public key present in the built Info.plist, the
  mach-lookup entitlements on the running binary, and the menu item.
- Local dry run before publishing: install 1.2, point its feed at a scratch
  appcast holding a 1.2.1 build via the `SUFeedURL` user-defaults override, and
  confirm the install-and-relaunch flow in the sandbox.
