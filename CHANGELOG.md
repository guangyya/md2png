# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
