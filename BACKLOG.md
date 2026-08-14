# Product backlog

This file records the product rationale and constraints for ideas that fit
md2png. The live workflow state, priority, and effort are maintained in the
[`md2png Backlog` GitHub Project](https://github.com/users/guangyya/projects/1);
each candidate has one linked issue as its execution record.

Backlog placement is not a promise of a release, date, or final design. Priority
can change after user feedback, technical investigation, or privacy review.

## Status and priority

| Status | Meaning |
|---|---|
| Ready for design | The problem fits the product and is the next candidate for detailed design |
| Proposed | Worth keeping, but needs validation or a clearer design before implementation |
| Deferred | Valid idea whose complexity or scope is not justified yet |
| Completed | Shipped behavior retained here as a concise product-work record |

| Priority | Meaning |
|---|---|
| P1 | Highest-value candidate for an upcoming release |
| P2 | Useful follow-up after higher-value work |
| P3 | Revisit only when stronger demand or enabling work appears |

Effort is relative rather than a time commitment: **S** is an isolated change,
**M** spans multiple components or test surfaces, and **L** affects the renderer,
packaging, broad UI behavior, or contains meaningful design uncertainty.

Use the Project rather than this file as the single source of truth for current
workflow state. This index keeps stable IDs, issue links, dependencies, and
coordination notes close to the repository.

## Planning index

| ID | Issue | Effort | Dependencies / coordination |
|---|:---:|:---:|---|
| FEAT-001 | [#1](https://github.com/guangyya/md2png/issues/1) | L | Coordinate preview commands with FEAT-012 and accessibility with TD-004 |
| FEAT-002 | [#2](https://github.com/guangyya/md2png/issues/2) | L | Prefer FEAT-001 Save/export foundations before designing split output |
| FEAT-003 | [#3](https://github.com/guangyya/md2png/issues/3) | M | Settings delivery plan and FEAT-012 menu state |
| FEAT-004 | [#4](https://github.com/guangyya/md2png/issues/4) | L | Settings delivery plan, TD-001 SwiftUI path, and TD-004 |
| FEAT-005 | [#5](https://github.com/guangyya/md2png/issues/5) | L | Requires packaging, signing, and cross-application investigation |
| FEAT-006 | [#6](https://github.com/guangyya/md2png/issues/6) | L | Settings delivery plan, FEAT-012 menu state, and per-theme renderer tests |
| FEAT-007 | [#7](https://github.com/guangyya/md2png/issues/7) | M | Settings delivery plan and FEAT-012 copy/menu placement |
| FEAT-008 | [#8](https://github.com/guangyya/md2png/issues/8) | M | TD-001 SwiftUI path, TD-004, and FEAT-012 terminology |
| FEAT-009 | [#9](https://github.com/guangyya/md2png/issues/9) | M | FEAT-012 menu placement and clipboard ownership handling |
| FEAT-010 | [#10](https://github.com/guangyya/md2png/issues/10) | L | Coordinate with TD-002, TD-003, TD-004, and TD-005 |
| FEAT-011 | [#11](https://github.com/guangyya/md2png/issues/11) | M | FEAT-012 menu placement and file-access validation |
| FEAT-012 | [#12](https://github.com/guangyya/md2png/issues/12) | M | Cross-cutting coordination for every item that adds UI or messages |
| FEAT-013 | [#18](https://github.com/guangyya/md2png/issues/18) | L | FEAT-012 menu/messages, signed release assets, and packaged project URL |

## Settings delivery plan

The accepted candidates now provide enough content for a focused Settings
window, but the app should not ship an empty preferences shell ahead of those
features. Introduce Settings when configurable shortcuts are implemented or
when at least two of render width, render theme, and Launch at Login are ready
to ship together.

Organize the window into **General** (Launch at Login), **Rendering** (theme and
width), and **Shortcuts**. Keep frequently changed theme and width choices in
the menu as quick actions, with Settings reflecting the same stored values.

## Ready for design

<details>
<summary><strong>FEAT-001: Last Render preview actions</strong></summary>

- **Priority:** P1
- **Problem:** The preview confirms the output, but saving or reusing it requires
  another clipboard or application step.
- **Candidate scope:** Add a compact preview action area for **Copy Again**,
  **Save PNG…**, **Open in Preview**, and dragging the image to another app.
  Add inspection controls for **Fit to Window**, **Actual Size**, **Zoom In**,
  and **Zoom Out**.
- **Constraints:** Keep the current uncluttered preview, avoid silently saving a
  history, and create temporary drag files only when the user starts a drag.
  Zoom changes only the preview presentation, never the generated image or
  clipboard contents; opening a render should still start in a predictable fit
  mode with correct centering and top position. Define **Actual Size**
  consistently against PNG pixel dimensions and Retina backing scale before
  implementation.
- **Validation:** Cover toolbar keyboard access, fit and actual-size geometry,
  zoom limits, tall and wide images, window resizing, scrolling, and the
  existing Command-W behavior.
- **Tracking issue:** [#1](https://github.com/guangyya/md2png/issues/1)

</details>

<details>
<summary><strong>FEAT-008: First-launch guide</strong></summary>

- **Priority:** P2
- **Problem:** A menu bar-only app can appear to do nothing after launch, and a
  new user may not discover the copy, shortcut, and paste workflow or know
  whether global shortcuts registered successfully.
- **Candidate scope:** Show a compact welcome window on the first successful
  launch with the three-step workflow, the current Render and Show Last Render
  shortcuts and their registration status, a **Try a Short Sample** action, and
  a clear **Done** action. Add **Show Welcome…** to the menu so it can be opened
  again later.
- **Constraints:** Show it only once by default, store only the completed flag,
  and do not request permissions, enable Launch at Login, contact a server, or
  read/render clipboard content automatically. Trying a sample must remain an
  explicit action.
- **Validation:** Cover first and subsequent launches, reopening from the menu,
  shortcut-conflict presentation, the sample action, keyboard navigation, and
  English and Simplified Chinese layouts.
- **Tracking issue:** [#8](https://github.com/guangyya/md2png/issues/8)

</details>

<details>
<summary><strong>FEAT-012: Menu, message, and localization polish</strong></summary>

- **Priority:** P2
- **Problem:** Accepted features will add commands, states, and errors to a
  compact menu bar app. Without a stable hierarchy and shared language rules,
  the menu will become harder to scan and English and Simplified Chinese copy
  will drift or expose overly technical messages.
- **Candidate scope:** Keep primary render and preview actions at the top,
  rendering choices and Examples in shallow submenus, and infrequent app/help
  commands below a separator. Use the following target hierarchy, adding
  feature-dependent items only when their owning backlog item ships:

  ```text
  Clipboard Preview
  ──────────────────
  Render Clipboard as Image
  Render Markdown File…
  Render Last Markdown Again
  Restore Last Markdown
  Show Last Render
  ──────────────────
  Theme ›
  Width ›
  Examples ›
  ──────────────────
  Settings…
  Show Welcome…
  About md2png
  ──────────────────
  Quit md2png
  ```

- **Menu rules:** Keep ordering stable, disable temporarily unavailable
  commands instead of moving them, show selected Theme and Width with
  checkmarks, avoid submenus deeper than one level, and keep global-shortcut
  labels visible for the primary Render and Show Last Render commands.
- **Message rules:** Prefer concise, action-first labels. Success messages state
  what changed and the next action; error summaries state what failed, confirm
  clipboard safety when relevant, and offer a recovery action. Keep raw
  Mermaid, JavaScript, WebKit, and system details in the diagnostics view rather
  than the primary HUD. Use ellipses consistently only when another window or
  user choice is needed to complete a command.
- **Localization rules:** Maintain identical localization key sets, avoid
  concatenating translated fragments, use positional format strings for values,
  and keep product terms such as Markdown, Mermaid, PNG, Render, Last Render,
  Example, and Settings consistent across the app, About, onboarding, errors,
  README files, and screenshots.
- **Validation:** Review the full menu in English and Simplified Chinese with
  empty, text, image, rendering, success, failure, and shortcut-conflict states.
  Check keyboard access, VoiceOver names, truncation, multiline wrapping,
  terminology consistency, and localization key parity.
- **Tracking issue:** [#12](https://github.com/guangyya/md2png/issues/12)

</details>

<details>
<summary><strong>FEAT-013: Check for updates and download</strong></summary>

- **Priority:** P2
- **Problem:** Once md2png is installed, users have no direct way to discover
  and retrieve a newer signed release without manually navigating GitHub.
- **Candidate scope:** Put update discovery in About instead of adding another
  menu command. When About opens, silently request the public GitHub latest-
  release JSON when the cached successful result is stale, then compare its
  stable tag with the installed `CFBundleShortVersionString`. Keep automatic
  checking silent. Once resolved, show an icon and either **Up to
  Date** with **Check Again**, or **Version x.y.z is available** with **Download
  Update**. Download only after that explicit click, show compact progress in
  the same row and the status item, verify the versioned Apple-silicon DMG, and
  open it with `NSWorkspace` when complete. Do not show a checking or download
  dialog, and keep GitHub pages out of the successful flow. When the user clicks
  **Check Again**, change that inline action to **Checking…**, then **Checked
  just now** through the local cooldown so the request has durable feedback.
- **Implementation flow:** Use
  `GET https://api.github.com/repos/{owner}/{repo}/releases/latest` as the update
  manifest. Separate silent discovery from the user-triggered download flow:
  unknown/cached result → up to date or update available, then download with
  progress and cancellation → verifying → opening DMG → prompting the user to
  drag md2png into Applications. Keep one shared coordinator so only one check
  or download can run at a time. Preserve a displayed cached result while a
  silent refresh runs, update the menu bar icon only for download milestones,
  and announce resolved results and phase changes to VoiceOver without
  announcing checking or every percentage update.
- **Caching and rate limits:** Persist a successful release response for 24
  hours. Opening About within that interval must resolve the cached response
  without a network request. **Check Again** bypasses the 24-hour cache but
  permits at most one actual request per 60 seconds. If GitHub responds with
  HTTP 403 or 429, honor `Retry-After`, or `X-RateLimit-Reset` when the remaining
  quota is zero, persist the retry time across launches, and disable retry until
  then. Keep a single request in flight and do not rely on unauthenticated ETag
  requests to avoid GitHub's shared-IP rate limit.
- **Version and publishing contract:** Keep `Info.plist` as the single version
  source. Compare the installed `CFBundleShortVersionString` with the optional-
  `v` release tag using numeric semantic-version components; use
  `CFBundleVersion` only as the monotonically increasing build number. The
  release tag must be `v{version}`, the changelog section must match `{version}`,
  and the downloadable asset must be
  `md2png-{version}-macOS-arm64-developer-id.dmg`. The existing release script
  should derive these values and verify the published asset metadata.
- **Release asset contract:** From the latest non-draft, non-prerelease release,
  select exactly one asset named
  `md2png-{version}-macOS-arm64-developer-id.dmg` with the expected disk-image
  content type, positive size, HTTPS download URL, and SHA-256 digest. Download
  into `~/Library/Caches/io.github.guangyya.md2png/Updates/` through a temporary
  file, require the received size and digest to match the release metadata,
  remove partial or invalid files, and rely on the existing Developer ID
  signature, notarization, stapling, and macOS Gatekeeper when opening the
  verified DMG. Keep the verified DMG available for **Open** and **Show in
  Finder**, so users can locate or remove the cached download themselves.
- **Installation boundary:** Opening the DMG is the final automated step. Do not
  replace the running app, copy into Applications, request elevated privileges,
  relaunch, or claim installation has completed. After the DMG opens, clearly
  tell the user to drag md2png to Applications to finish the update.
- **Failure fallback:** Check, metadata, version, download, integrity, file, or
  open failures must preserve the installed app, remove unusable temporary
  files, and expose inline **Try Again** or **Retry Download** plus **View
  Releases** in About. A download failure may also use the non-activating HUD
  when About is closed. Never open GitHub automatically after a failure.
- **Privacy and network constraints:** Never check at launch, during rendering,
  on a background timer, or anywhere other than About. Do not add Sparkle, an
  updater helper, credentials, telemetry, or automatic retries. Send no
  Markdown, clipboard data, device identifier, or account data; make at most
  one check/download active at a time; use bounded timeouts; support download
  cancellation; and keep rendering fully available offline.
- **Version rules:** Compare normalized numeric release versions rather than
  strings, accept an optional leading `v`, and treat malformed or unsupported
  tags as a failure rather than claiming the app is current.
- **Validation:** Cover newer, equal, and older versions; `1.10.0` versus
  `1.9.0`; optional `v` prefixes; missing, duplicate, wrong-architecture,
  wrong-type, wrong-size, or wrong-digest assets; no published release;
  malformed JSON; offline, timeout, redirect, HTTP, and rate-limit failures;
  cancellation and repeated clicks; 24-hour cached checks; the 60-second manual
  cooldown; persisted `Retry-After` and rate-limit reset handling; cache cleanup;
  DMG open success/failure; no visible Checking state; milestone-only VoiceOver
  announcements; missing or non-GitHub project URLs; English and Simplified
  Chinese copy; and proof that launch and normal rendering make no network
  request.
- **Tracking issue:** [#18](https://github.com/guangyya/md2png/issues/18)

</details>

## Proposed

<details>
<summary><strong>FEAT-002: Split very tall renders</strong></summary>

- **Priority:** P2
- **Problem:** A single tall image can be hard to review or paste, and content
  beyond the renderer's height limit cannot be exported.
- **Candidate scope:** Offer an explicit split/export flow with numbered PNGs.
  Prefer boundaries between blocks rather than cutting table rows, code blocks,
  or Mermaid diagrams.
- **Open questions:** Whether clipboard paste can represent multiple images
  consistently across chat clients, and whether splitting should be Save-only.
- **Tracking issue:** [#2](https://github.com/guangyya/md2png/issues/2)

</details>

<details>
<summary><strong>FEAT-003: Render width presets</strong></summary>

- **Priority:** P2
- **Problem:** Chat-sized prose, wide tables, and large diagrams benefit from
  different output widths.
- **Candidate scope:** Provide **Compact**, **Standard**, and **Wide** presets and
  remember the last explicit selection locally.
- **Constraints:** Avoid a general CSS/theme editor and keep Standard identical
  to today's output unless intentionally changed in a release.
- **Tracking issue:** [#3](https://github.com/guangyya/md2png/issues/3)

</details>

<details>
<summary><strong>FEAT-004: Configurable global shortcuts</strong></summary>

- **Priority:** P2
- **Problem:** System-wide shortcuts can conflict with browsers, developer
  tools, conferencing clients, or other menu bar utilities.
- **Candidate scope:** Add a small Settings window for Render and Show Last
  Render, conflict detection, and Restore Defaults.
- **Constraints:** Keep menu commands usable when registration fails and do not
  require Accessibility permission.
- **Tracking issue:** [#4](https://github.com/guangyya/md2png/issues/4)

</details>

<details>
<summary><strong>FEAT-006: Built-in render themes</strong></summary>

- **Priority:** P2
- **Problem:** The current light rendering style works well for general content,
  but code-heavy, long-form, and dark-environment sharing can benefit from a
  different visual treatment.
- **Candidate scope — Phase 1:** Add three bundled, explicitly selected themes:
  **Clean Light** (the current look and default), **Warm Paper**, and **Dark**.
  Apply the selected theme to shortcut, menu, and Example renders, and remember
  the selection locally.
- **Theme boundaries:** Themes may change colors, surfaces, borders, syntax
  highlighting, and Mermaid palettes. Keep typography, spacing, render width,
  and diagram layout consistent across themes. Use an opaque background and do
  not add arbitrary CSS, custom fonts, or a general theme editor.
- **Follow-up plan — System/Auto:** After the explicit themes are stable, assess
  an opt-in **System/Auto** choice that resolves to Clean Light or Dark from the
  effective macOS appearance at the moment rendering starts. The resolved theme
  must be fixed in the generated PNG; existing renders must never change when
  system appearance changes.
- **System/Auto constraints:** Do not infer destination-app or recipient
  appearance. Fall back to Clean Light when system appearance cannot be
  resolved, and cover both light and dark resolution paths with deterministic
  tests before shipping.
- **Validation:** Exercise prose, tables, code highlighting, flowcharts,
  sequence diagrams, and Gantt diagrams in every theme; verify consecutive
  theme switches do not leak styles and do not unexpectedly change layout.
- **Tracking issue:** [#6](https://github.com/guangyya/md2png/issues/6)

</details>

<details>
<summary><strong>FEAT-007: Launch at login</strong></summary>

- **Priority:** P2
- **Problem:** A menu bar companion is most useful when it is already available
  after a Mac restart, but launching it manually each time is easy to forget.
- **Candidate scope:** Add an explicit **Launch at Login** toggle backed by the
  native macOS main-app login service. Reflect the effective system state and
  provide a clear error or System Settings route when registration needs user
  attention.
- **Constraints:** Keep the option off by default, do not prompt on first
  launch, and do not install a separate helper, daemon, updater, or background
  worker. Disabling the option must unregister the login item cleanly.
- **Validation:** Verify enable, disable, restart, user-denied, and externally
  changed Login Items states with an installed signed build. A login launch must
  remain an accessory/menu bar launch without showing a Dock icon or window.
- **Tracking issue:** [#7](https://github.com/guangyya/md2png/issues/7)

</details>

<details>
<summary><strong>FEAT-010: Renderer diagnostics</strong></summary>

- **Priority:** P2
- **Problem:** A transient error HUD confirms that rendering failed but may not
  provide enough durable, actionable detail to correct Mermaid syntax or
  distinguish content, renderer-resource, and WebKit failures.
- **Candidate scope:** Return structured renderer errors and provide a compact
  details view with a clear summary, the Mermaid diagram number and source line
  when available, hints for common fence or diagram-type mistakes, and **Copy
  Error Details**. Add **Run Renderer Self-Test** to About using a bundled input
  without reading or changing the clipboard.
- **Constraints:** Keep diagnostics local and never upload logs. Persist only
  the bounded, allowlisted, privacy-safe events defined by TD-005; never save
  Markdown, clipboard text, rendered image data, or raw errors that may contain
  them. Exclude the user's full Markdown from copied details unless the user
  explicitly chooses to include it. Diagnostics must not turn into a Markdown
  editor or silently rewrite source.
- **Validation:** Cover invalid Mermaid, unavailable bundled resources, invalid
  renderer responses, size limits, a terminated WebKit content process,
  localization, clipboard preservation, and a self-test that leaves clipboard
  contents unchanged.
- **Tracking issue:** [#10](https://github.com/guangyya/md2png/issues/10)

</details>

## Deferred

<details>
<summary><strong>FEAT-005: macOS Services action</strong></summary>

- **Priority:** P3
- **Problem:** Rendering selected Markdown currently requires an explicit copy
  before invoking md2png.
- **Candidate scope:** Expose **Render with md2png** through macOS Services for
  selected text.
- **Why deferred:** Packaging, discovery, signing, and cross-application
  behavior need investigation; the existing permission-free global shortcut is
  already reliable.
- **Tracking issue:** [#5](https://github.com/guangyya/md2png/issues/5)

</details>

<details>
<summary><strong>FEAT-011: Render a Markdown file</strong></summary>

- **Priority:** P3
- **Problem:** Rendering an existing long Markdown file requires opening it,
  selecting its content, and copying it before using the normal workflow.
- **Candidate scope:** Add an explicit **Render Markdown File…** command that
  selects one local `.md`, `.markdown`, or `.txt` file and sends its text
  through the same renderer and clipboard output path.
- **Constraints:** Do not add an editor, recent-file history, directory
  monitoring, persistent file access, or security-scoped bookmarks. Preserve
  the file and clipboard on failure, keep external images blocked, and apply
  the existing render-size limits. Accept UTF-8 text only in the initial scope
  and report unsupported or invalid encoding clearly.
- **Why deferred:** The clipboard workflow already covers the primary use case,
  while file encoding, access errors, and another menu command add complexity
  for an unvalidated lower-frequency path.
- **Tracking issue:** [#11](https://github.com/guangyya/md2png/issues/11)

</details>

## Completed

<details>
<summary><strong>FEAT-009: Last Source actions</strong></summary>

- **Shipped behavior:** Keep only the latest successfully rendered Markdown in
  memory and provide **Render Last Markdown Again** and **Restore Last
  Markdown**. Both actions are disabled until a render succeeds and the source
  is discarded when md2png quits.
- **Clipboard safety:** Track md2png's latest clipboard write and require
  confirmation before a Last Markdown action replaces content changed by
  another application. Cancelling preserves the newer clipboard content.
- **Tracking issue:** [#9](https://github.com/guangyya/md2png/issues/9)

</details>

## Not planned

The following directions conflict with the current product definition and
should not be added to the backlog without an explicit product decision:

- Automatically paste or send content to another application.
- Upload Markdown or rendered images for cloud processing or synchronization.
- Monitor the clipboard and render automatically in the background.
- Keep a persistent render history by default.
- Turn the menu bar companion into a full Markdown editor.
- Add scheduled background or launch-time update checks, silently replace the
  installed app, or add a repository credential.
- Add Intel (`x86_64`) distribution without demonstrated user demand.

## Maintenance rules

- Use a stable `FEAT-###` identifier in related issues, commits, and release
  notes.
- Keep design and implementation discussion in the linked issue rather than
  expanding this file indefinitely.
- When an item ships, move its Project status to **Done**, close the linked
  issue, move its product summary to the **Completed** section, and record the
  shipped behavior and version in `CHANGELOG.md`.
- Track internal refactors and architecture work separately in
  [`TECH_DEBT.md`](TECH_DEBT.md); do not present them as product features.
- Reject or defer ideas that weaken local rendering, manual sending, or the
  permission-friendly core workflow.
