# About panel design

Date: 2026-09-04

## Goal

An About page reachable from the status menu, showing what users expect: icon,
name, version and build, copyright, and where to find the website and source.

## Decision

Apple's standard About panel via `orderFrontStandardAboutPanel(options:)`.
It reads the icon, name, version, build, and copyright from the bundle, so the
app supplies only a credits block. A custom window was considered and rejected:
nothing on the page needs live state, and the standard panel is what users
recognise.

## Details

- Menu item "About PhotoDrift" after "Check for Updates...".
- The app is an `LSUIElement` agent, so the panel is shown after
  `NSApp.activate(ignoringOtherApps:)`, as the Settings window already is.
- Credits: a short attributed string with links to the product page, the GitHub
  repository, and Sparkle. Built by a pure static so it can be tested without a
  window.

## Verification

Tests check the credits contain the three links and stay short enough for the
panel's small credits area. Opening the panel is checked by hand.
