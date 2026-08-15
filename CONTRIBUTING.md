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
not only a proposed implementation. Search the repository's
[public GitHub Issues](https://github.com/guangyya/md2png/issues) first.

Issues labeled `backlog` contain ideas that have passed an initial product-fit
review. They are not a committed roadmap. Each accepted product or
technical-debt item uses its GitHub issue as the single source for scope,
constraints, and validation.

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
- User-visible features and fixes: keep the complete notes under `Unreleased`
  in `CHANGELOG.md` and the concise, one-line in-app highlights under
  `Unreleased` in `ABOUT_CHANGELOG.md`. Release preparation refuses an empty or
  malformed section and moves both sections without generating copy.

## Continuous integration

Pull requests targeting `main` and pushes to `main` run independent checks on
macOS 15 with Xcode 26.2 and macOS 26 with Xcode 26.6. Both stable checks are
required. An `Xcode 27 preview` check exercises the preview compiler and SDK on
macOS 26 without blocking merges. Matrix fail-fast is disabled so every check
finishes and reports its own result when another environment fails.

Every check uses Node.js 24.18.0 and pnpm 11.19.0, installs the committed
renderer lockfile in frozen mode, runs `make test`, and uses `make verify-dist`
to build and verify the release-configured arm64 app. The packaged self-test
renders bundled Markdown, a GFM table, highlighted code, and Mermaid through
the production renderer without touching the clipboard. Stable jobs select an
exact Xcode installation; the preview job follows GitHub's versioned
`xcode-27` preview image.

CI also fails when renderer regeneration changes the committed bundle or when
the app has the wrong identity, project URL, architecture, ad-hoc signature, or
required packaged resources. It uses a read-only workflow token and does not
consume or publish caches, artifacts, release credentials, tags, or Releases.
When updating the toolchain, keep versions explicit and update each referenced
action to a reviewed immutable commit SHA.

### Test coverage

Run the same source-line coverage measurement used by the official Release
workflow with:

```sh
make coverage
```

The command runs SwiftPM tests with coverage enabled, then writes deterministic
JSON and Markdown summaries to `.build/coverage/`. The metric includes every
Swift file under `Sources/MD2PNG/`; test files, dependencies, generated package
accessors, renderer JavaScript, and other build output are outside that source
set. The summaries contain counts and repository-relative paths only. Raw
profiles, absolute paths, source text, fixtures, and rendered content must not
be uploaded.

Pull requests and ordinary CI pushes to `main` do not collect coverage. They
continue to run the normal compatibility test matrix, including the focused
report-generator tests, without repeating the full Swift test suite in a
separate coverage job. Only a version-changing Release PR merge starts the
trusted Release build; that publisher collects coverage once on canonical Xcode
26.2, validates it before publication, and uploads the normalized JSON and
Markdown summaries with the Release.

Stable Release JSON assets provide the durable version history. Pinned issue
[#42](https://github.com/guangyya/md2png/issues/42) is the fixed dashboard
target, independent of its title or open/closed state. It contains a derived
chart and accessible table; missing or malformed release snapshots are reported
there rather than silently omitted.

## Pull requests

- Keep each pull request focused on one behavior or bug.
- Add or update tests for observable behavior.
- Update README or release documentation when the user workflow changes.
- Keep `README.md` and `README.zh-Hans.md` aligned for installation and core
  workflow changes.
- Update the issue and GitHub Project fields when a candidate is accepted,
  deferred, implemented, or rejected; avoid duplicating the backlog in another
  roadmap file.
- Do not commit generated build directories, app bundles, ZIP files, or secrets.
