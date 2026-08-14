# Product brief

md2png is a local-first macOS menu bar companion that converts clipboard
Markdown into a paste-ready PNG without uploading, pasting, or sending content.

## Problem

Many chat clients support only part of Markdown. GFM-style tables, highlighted
code, and Mermaid diagrams may appear as unformatted source. Using a separate
editor, taking a screenshot, cropping it, and returning to the chat is too slow
for everyday project updates.

## Product decision

Use a standalone native companion rather than modifying or injecting code into
another application:

```text
Copy Markdown -> Control-Command-X -> local render -> PNG clipboard -> paste -> review -> send
```

The image keeps table and diagram layout consistent across desktop and mobile
clients. The sender always reviews the attachment and remains responsible for
sending it.

## Product principles

- **Explicit:** copy, render, paste, review, and send remain separate user
  actions.
- **Local:** message content and rendered pixels stay on the Mac.
- **Permission-friendly:** the basic workflow does not need Accessibility
  permission.
- **Independent:** no destination-app login, API, bot, extension, or internal
  integration.
- **Small and native:** Swift, AppKit, Carbon hot keys, WebKit, and bundled web
  renderer assets instead of Electron.

## Current scope

- Apple silicon Macs running macOS 14 or newer.
- Standard Markdown, GFM-style tables, checklist source, strikethrough, and
  syntax-highlighted fenced code.
- Mermaid fences including flowcharts, sequence diagrams, and Gantt charts.
- Retina-friendly PNG/TIFF clipboard output.
- Global render and last-preview shortcuts plus equivalent menu commands.
- Compact clipboard preview, non-activating HUD, and an in-memory preview of the
  latest successful render.
- Short, long, formatting, code, checklist, table, flowchart, sequence, and
  Gantt samples that render immediately when selected.
- English and Simplified Chinese UI selected from macOS language settings.
- About window with Debug/Release identification, version/build/source commit,
  release notes, project link, update action, and copyable diagnostics.
- Silent update discovery in About, backed by a 24-hour successful-result cache
  and a rate-limited **Check Again** action. A newer signed DMG downloads only
  after **Download Update** is clicked, is verified, and opens for the user to
  finish installation. Progress stays in the About row and status item, with
  milestone-only VoiceOver announcements rather than a modal progress window.
- Duplicate render entry points disabled while one render is in progress.

## Safety and privacy constraints

- Never send, paste, or upload message content automatically.
- Preserve clipboard Markdown when a clipboard render fails.
- Disable raw Markdown HTML and sanitize generated HTML.
- Block external Markdown images so rendering cannot fetch a message-derived URL.
- Bundle all JavaScript, CSS, localization, and examples required at runtime.
- Keep the last render in memory only; do not create a content history.

## Deliberate non-goals

- Editing Markdown inside the app.
- Monitoring or intercepting another application's messages.
- Launch-time or scheduled update checks, silent app replacement, or an embedded
  GitHub credential.
- Cloud rendering, shared storage, analytics, or telemetry.
- Intel (`x86_64`) distribution.

## Backlog

Candidate features and deliberately deferred ideas are maintained in the
repository's single [Product backlog](../BACKLOG.md). Backlog placement confirms
product fit, not a release date or implementation commitment.
