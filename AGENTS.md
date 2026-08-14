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

## Git and pull request workflow

- Never modify, commit, or push changes directly on `main`.
- Read-only investigation and explanation do not require a branch.
- Before changing files, update a clean `main` from `origin/main` with a
  fast-forward-only pull, then create a focused topic branch using the
  `codex/` prefix.
- If the main worktree contains user changes, preserve them in place and use an
  isolated worktree from `origin/main`; never move, stash, or commit them
  without explicit permission.
- Implement and verify the requested change on the topic branch. Commit only
  files belonging to that change, push the branch, and open a pull request
  targeting `main` unless the user explicitly asks not to publish it.
- Never merge a pull request without a separate explicit user request.
- After the user confirms a merge, fast-forward local `main`, prune remote
  references, and delete the merged topic branch when its changes are safely
  present on `main`.

## Verification

Run `make test` and `make app`. Test the built app with `make run`.
