# Contributing

Thanks for helping improve md2png. Keep changes aligned with the app's
small, local-first scope.

## Product boundaries

- Never paste or send content automatically.
- Never upload Markdown or rendered content to a server.
- Keep the basic clipboard workflow free of Accessibility permission.
- Bundle rendering scripts and styles inside the application.
- Preserve the original clipboard Markdown when rendering fails.
- Prefer native Swift, AppKit, and WebKit over a browser runtime.

## Development setup

```sh
make bootstrap
make test
make app CONFIGURATION=debug
make run CONFIGURATION=debug
```

`make bootstrap` installs the renderer dependencies and regenerates the bundled
renderer. Generated build output, app bundles, ZIPs, DMGs, and credentials must
not be committed.

## Feature requests

Use the repository's Feature Request issue form and start with the user problem,
not only a proposed implementation. Search existing issues and
[`BACKLOG.md`](BACKLOG.md) first.

The backlog contains ideas that have passed an initial product-fit review. It is
not a committed roadmap. Maintainers assign stable `BL-###` identifiers and link
tracking issues when a candidate is ready for deeper design.

## Verification

- Swift or AppKit changes: run `make test`, `make app CONFIGURATION=debug`, and
  test the built app with `make run CONFIGURATION=debug`.
- Renderer changes: also verify plain Markdown, a GFM table, highlighted code,
  one flowchart, and the long sample in the running app.
- Localization changes: add every key to both `en.lproj` and `zh-Hans.lproj` and
  keep the localization key-set test passing. Avoid concatenated translated
  fragments and verify terminology, formatting arguments, truncation, and
  multiline wrapping in both languages.
- Menu, window, or custom-control changes: verify Full Keyboard Access,
  VoiceOver labels and states, standard Command-W/Command-Comma/Return/Escape
  behavior where applicable, Increase Contrast, and Reduce Motion.
- User-facing messages: keep the primary copy concise and actionable, confirm
  clipboard safety when relevant, and place technical renderer details in the
  diagnostics surface rather than the HUD.
- Documentation changes: verify relative links, command names, shortcuts,
  release filenames, and checked-in render screenshots.
- User-visible behavior: add an entry under `Unreleased` in `CHANGELOG.md`.

## Continuous integration

Pull requests targeting `main` and pushes to `main` run independent checks on
macOS 15 with Xcode 26.2 and macOS 26 with Xcode 26.6. Both stable checks are
required. An `Xcode 27 preview` check exercises the preview compiler and SDK on
macOS 26 without blocking merges. Matrix fail-fast is disabled so every check
finishes and reports its own result when another environment fails.

Every check uses Node.js 24.18.0 and pnpm 11.19.0, installs the committed
renderer lockfile in frozen mode, runs `make test`, and builds and verifies the
release-configured arm64 app. Stable jobs select an exact Xcode installation;
the preview job follows GitHub's versioned `xcode-27` preview image.

CI also fails when renderer regeneration changes the committed bundle or when
the app has the wrong identity, project URL, architecture, ad-hoc signature, or
required packaged resources. It uses a read-only workflow token and does not
consume or publish caches, artifacts, release credentials, tags, or Releases.
When updating the toolchain, keep versions explicit and update each referenced
action to a reviewed immutable commit SHA.

## Pull requests

- Keep each pull request focused on one behavior or bug.
- Add or update tests for observable behavior.
- Update README or release documentation when the user workflow changes.
- Keep `README.md` and `README.zh-Hans.md` aligned for installation and core
  workflow changes.
- Update `BACKLOG.md` when a candidate is accepted, deferred, implemented, or
  rejected; avoid duplicating the backlog in another roadmap file.
- Do not commit generated build directories, app bundles, ZIP files, or secrets.
