# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

No unreleased changes.

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
