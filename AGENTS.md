# Working agreement

This repository contains a small, native macOS companion app. Keep it local-first,
offline after installation, and independent of other applications' internals and
APIs.

## Product invariants

- Never paste or send content automatically.
- Never upload Markdown or rendered content to a server.
- The basic clipboard workflow must not require Accessibility permission.
- Bundle all rendering scripts and styles inside the application.
- Preserve the user's Markdown in the clipboard if rendering fails.
- Prefer native Swift/AppKit/WebKit over Electron.

## Verification

Run `make test` and `make app`. Test the built app with `make run`.
