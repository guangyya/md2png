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
| BL-001 | [#1](https://github.com/guangyya/md2png/issues/1) | L | Coordinate preview commands with BL-012 and accessibility with TD-004 |
| BL-002 | [#2](https://github.com/guangyya/md2png/issues/2) | L | Prefer BL-001 Save/export foundations before designing split output |
| BL-003 | [#3](https://github.com/guangyya/md2png/issues/3) | M | Settings delivery plan and BL-012 menu state |
| BL-004 | [#4](https://github.com/guangyya/md2png/issues/4) | L | Settings delivery plan, TD-001 SwiftUI path, and TD-004 |
| BL-005 | [#5](https://github.com/guangyya/md2png/issues/5) | L | Requires packaging, signing, and cross-application investigation |
| BL-006 | [#6](https://github.com/guangyya/md2png/issues/6) | L | Settings delivery plan, BL-012 menu state, and per-theme renderer tests |
| BL-007 | [#7](https://github.com/guangyya/md2png/issues/7) | M | Settings delivery plan and BL-012 copy/menu placement |
| BL-008 | [#8](https://github.com/guangyya/md2png/issues/8) | M | TD-001 SwiftUI path, TD-004, and BL-012 terminology |
| BL-009 | [#9](https://github.com/guangyya/md2png/issues/9) | M | BL-012 menu placement and clipboard ownership handling |
| BL-010 | [#10](https://github.com/guangyya/md2png/issues/10) | L | Coordinate with TD-002, TD-003, TD-004, and TD-005 |
| BL-011 | [#11](https://github.com/guangyya/md2png/issues/11) | M | BL-012 menu placement and file-access validation |
| BL-012 | [#12](https://github.com/guangyya/md2png/issues/12) | M | Cross-cutting coordination for every item that adds UI or messages |

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
<summary><strong>BL-001: Last Render preview actions</strong></summary>

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
<summary><strong>BL-008: First-launch guide</strong></summary>

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
<summary><strong>BL-009: Last Source actions</strong></summary>

- **Priority:** P1
- **Problem:** A successful render replaces the clipboard Markdown with an
  image, so recovering the source or trying another theme or width requires
  finding and copying the original text again.
- **Candidate scope:** Keep the Markdown paired with the latest successful
  render in memory and add **Render Last Markdown Again** and **Restore Last
  Markdown**. Re-rendering uses the currently selected theme and width.
- **Constraints:** Never persist the source, embed it in the PNG, or create a
  history. Clear it when the app quits, enable actions only after a successful
  render, and require confirmation before overwriting clipboard content that
  changed after md2png last wrote its image.
- **Validation:** Cover successful, failed, and Example renders; unchanged and
  externally changed clipboards; theme and width changes; repeated actions; and
  confirmation that no source survives an app restart.
- **Tracking issue:** [#9](https://github.com/guangyya/md2png/issues/9)

</details>

<details>
<summary><strong>BL-012: Menu, message, and localization polish</strong></summary>

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

## Proposed

<details>
<summary><strong>BL-002: Split very tall renders</strong></summary>

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
<summary><strong>BL-003: Render width presets</strong></summary>

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
<summary><strong>BL-004: Configurable global shortcuts</strong></summary>

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
<summary><strong>BL-006: Built-in render themes</strong></summary>

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
<summary><strong>BL-007: Launch at login</strong></summary>

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
<summary><strong>BL-010: Renderer diagnostics</strong></summary>

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
<summary><strong>BL-005: macOS Services action</strong></summary>

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
<summary><strong>BL-011: Render a Markdown file</strong></summary>

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

No backlog items have been completed yet.

## Not planned

The following directions conflict with the current product definition and
should not be added to the backlog without an explicit product decision:

- Automatically paste or send content to another application.
- Upload Markdown or rendered images for cloud processing or synchronization.
- Monitor the clipboard and render automatically in the background.
- Keep a persistent render history by default.
- Turn the menu bar companion into a full Markdown editor.
- Add an embedded background updater or repository credential.
- Add Intel (`x86_64`) distribution without demonstrated user demand.

## Maintenance rules

- Use a stable `BL-###` identifier in related issues, commits, and release notes.
- Keep design and implementation discussion in the linked issue rather than
  expanding this file indefinitely.
- When an item ships, move its Project status to **Done**, close the linked
  issue, move its product summary to the **Completed** section, and record the
  shipped behavior and version in `CHANGELOG.md`.
- Track internal refactors and architecture work separately in
  [`TECH_DEBT.md`](TECH_DEBT.md); do not present them as product features.
- Reject or defer ideas that weaken local rendering, manual sending, or the
  permission-friendly core workflow.
