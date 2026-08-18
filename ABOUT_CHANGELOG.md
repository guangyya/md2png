# About Changelog

Concise release highlights shown inside About. See [CHANGELOG.md](CHANGELOG.md)
for the complete project history and release details.

## [Unreleased]

### Added

- Customize global shortcuts in Settings and restore their defaults.
- Save tall Markdown as numbered, block-aware PNGs without changing the clipboard.

### Changed

- Start without loading the renderer until the first render request.

### Fixed

- Open the Welcome Example list on the right without breaking its status-item
  anchor.
- Keep keyboard navigation inside the Welcome Example popover while it is open.
- Let VoiceOver finish speaking complete clipboard instructions from the HUD.
- Record shortcuts in Settings without activating them, show conflicts, and keep
  Restore Defaults available.

## [0.9.0] - 2026-08-17

### Added

- Get actionable renderer error details, including Mermaid diagram and line
  context when available.
- Run Renderer Self-Test or save privacy-safe diagnostic logs from About.

## [0.8.0] - 2026-08-17

### Added

- Preview release notes and install a signed update directly from About.
- Re-render the last Markdown with the current Theme and Output Width.

### Changed

- Scan a clearer menu and get more useful success and recovery messages.
- Keep Welcome usable on smaller screens and at larger text sizes.
- Make Warm Paper less yellow and code easier to read.

### Fixed

- Keep Fit compact in Last Render on newer macOS versions.

## [0.7.0] - 2026-08-17

### Added

- Choose Clean Light, Warm Paper, or Dark for every Markdown render.

## [0.6.0] - 2026-08-16

### Added

- Optionally launch md2png when you log in to your Mac.

## [0.5.0] - 2026-08-16

### Added

- Copy, save, open, and zoom the latest rendered image from Last Render.

## [0.4.0] - 2026-08-15

### Added

- Safely verify global shortcuts from Welcome.
- Learn the copy, render, and paste workflow from a first-launch guide.
- Choose Compact, Standard, or Wide output widths.

### Fixed

- Keep Welcome sample selection and menu handoff deterministic.
- Recover from interrupted or stalled WebKit renders without restarting the app.

## [0.3.0] - 2026-08-14

### Added

- Restore or copy the Markdown behind the latest successful render.
- Show the source commit in About and copied version diagnostics.

### Changed

- Keep in-app release notes brief and easy to scan.

## [0.2.0] - 2026-08-14

### Added

- Check for updates and securely download verified releases from About.

### Changed

- Show update status, progress, and actions directly in About.

## [0.1.0] - 2026-08-14

### Added

- Render clipboard Markdown to Retina PNG entirely on-device.
- Support GFM, highlighted code, and Mermaid diagrams.
- Add shortcuts, previews, examples, and English and Chinese localization.
- Ship a native Apple silicon menu bar app.
