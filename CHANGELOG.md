# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Save privacy-safe diagnostic logs for the last hour, 24 hours, or 7 days from
  About, using an explicit local save panel with no automatic upload.

## [0.8.0] - 2026-08-17

### Added

- Add an explicit signed update flow to About: preview bounded release notes,
  download and verify the versioned Apple silicon update, pause at Ready to
  Install, and choose Install and Relaunch or Later without leaving the app.
- Add a Re-render Last Markdown command that applies the current Theme and
  Output Width without requiring the source to be copied again.

### Changed

- Reorganize the status menu around frequent shortcuts, last-source recovery,
  rendering choices, and infrequent app commands; keep unavailable commands in
  place with accurate enabled states.
- Make English and Simplified Chinese success and error messages concise,
  recovery-oriented, and explicit about clipboard safety after render failures.
- Modernize the About presentation while keeping build identity, release
  history, project links, update state, and copyable diagnostics together.
- Make Welcome scroll and adapt to smaller displays and larger accessibility
  text sizes while keeping the full copy-render-paste journey visible.
- Tone down Warm Paper's yellow cast and strengthen code and Mermaid contrast.

### Fixed

- Keep Fit a compact momentary toolbar action on newer macOS versions instead
  of showing an oversized persistent selection state.

## [0.7.0] - 2026-08-17

### Added

- Add bundled Clean Light, Warm Paper, and Dark render themes with coordinated
  Markdown, syntax-highlighting, and Mermaid palettes, an opaque fixed output,
  and a locally remembered explicit selection shared by every render entry point.

## [0.6.0] - 2026-08-16

### Added

- Add opt-in Launch at Login controls to the menu and Welcome guide, backed by
  the native macOS main-app login service, including effective-state refresh
  and an explicit System Settings route when approval is required.

## [0.5.0] - 2026-08-16

### Added

- Add Last Render controls to copy the image again, save it as PNG, open it in
  Preview, fit it to the window, inspect it at pixel-accurate actual size, and
  zoom from 25% to 400% without changing the generated image.

## [0.4.0] - 2026-08-15

### Added

- Verify either registered global shortcut directly from Welcome without
  running its render or preview command.
- Add a first-launch guide for the copy, render, and paste workflow, including
  a native animated walkthrough, live global-shortcut status, an explicit
  menu-guided sample action, automatic example previews, and Command-Tab
  recovery while the guide is open.
- Add Compact, Standard, and Wide output-width presets and remember the last
  explicit selection locally.
- Add same-source Retina reference renders that show the presets' actual
  dimensions, wrapping, and table density.
- Add a one-choice Release PR workflow and an isolated hosted publisher that
  validates, signs, notarizes, publishes, verifies, and safely resumes the exact
  reviewed release commit.

### Changed

- Size the Last Render window to reflect the actual output width within the
  current screen, and identify the preset and dimensions in its title.

### Fixed

- Prevent hidden Welcome sample controls from receiving input, close the guide
  before the real status menu or sample render begins, and deliver each sample
  choice only once.
- Reload the bundled WebKit renderer after its content process terminates,
  retry the interrupted render once, and fail queued work deterministically if
  recovery cannot complete. A later user-initiated render starts a fresh local
  renderer load instead of requiring an app restart.
- Bound renderer page loads and render attempts with a watchdog so a missing
  WebKit callback cannot leave the app permanently stuck in Rendering. Timed
  out work fails once, while a later render starts a fresh local load.
- Isolate each renderer recovery in a new WebKit generation so missing or late
  process-termination callbacks cannot hide a later genuine termination.

## [0.3.0] - 2026-08-14

### Added

- Show the source commit for each build in About and copied version diagnostics.
- Add an offline packaged-renderer self-test and require it for CI and release
  artifacts before publication.
- Keep the latest successfully rendered Markdown in memory so it can be
  restored to the clipboard. External clipboard changes require confirmation
  before the action replaces them.

### Changed

- Keep the complete release history in the repository changelog while About
  uses a separate, concise set of release highlights.

## [0.2.0] - 2026-08-14

### Added

- Add silent update discovery in About using public GitHub latest-release
  metadata, a 24-hour successful-result cache, a 60-second manual cooldown, and
  persisted server rate-limit handling. A newer version downloads only after
  explicit confirmation; the app verifies the versioned Apple silicon DMG's
  size and SHA-256 digest before asking macOS to open it for manual installation.
  Verified downloads can be reopened or revealed in Finder for cleanup.

### Changed

- Replace the About window's manual Releases link with compact up-to-date or
  available-version status and inline actions. Automatic checking is silent;
  download progress stays in About and the status item, and Releases is a
  failure fallback.
- Give explicit update checks inline progress and recent-completion feedback
  without adding a dialog or changing the displayed release result.

## [0.1.0] - 2026-08-14

### Added

- Add a native Apple silicon macOS menu bar app that renders clipboard Markdown
  locally into Retina PNG and TIFF clipboard content.
- Support standard Markdown, GFM-style tables and checklists, syntax-highlighted
  fenced code, and bundled Mermaid flowcharts, sequence diagrams, and Gantt
  timelines.
- Add global shortcuts for rendering and showing the latest successful render,
  plus a compact clipboard preview and non-activating confirmation HUD.
- Add an in-memory Last Render preview with correct centering, tall-image
  scrolling, image dimensions, and standard Command-W behavior.
- Add bundled short, long, formatting, code, checklist, table, flowchart,
  sequence, and Gantt examples that render immediately when selected.
- Add English and Simplified Chinese localization, a structured About window,
  release notes, build diagnostics, and optional project and Releases links.
- Add offline rendering safeguards, including raw HTML sanitization, blocked
  external images, clipboard preservation on failure, and no automatic paste,
  upload, or send behavior.
- Add arm64 build, DMG, Developer ID signing, notarization, and configurable
  GitHub Release publishing workflows.
