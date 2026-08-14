# Technical debt

This file tracks internal architecture and maintenance work that does not by
itself add a product capability. Product candidates remain in
[`BACKLOG.md`](BACKLOG.md).

Technical-debt placement is not a promise of a release or date. A migration
must preserve observable behavior, privacy boundaries, supported macOS
versions, signing, packaging, and tests.

Priorities in this file mean: **P1** addresses an active reliability or release
risk, **P2** reduces recurring maintenance cost or enables accepted product
work, and **P3** is opportunistic cleanup that should accompany related work.

## Delivery order

1. **TD-002 packaged render self-test (P1)** before the next release workflow
   change, so release artifacts exercise their bundled renderer.
2. **TD-005 privacy-safe diagnostic logging (P2)** before or alongside
   structured renderer diagnostics and WebKit recovery.
3. **TD-003 WebKit content-process recovery (P2)** alongside structured renderer
   diagnostics.
4. **TD-004 accessibility and keyboard audit (P2)** as the first SwiftUI
   surfaces and expanded preview controls are implemented.
5. **TD-001 incremental SwiftUI rewrite (P3)** only through related product
   work, following its component migration order.

## TD-001: Incremental SwiftUI rewrite

- **Overall priority:** P3
- **Effort:** L
- **Dependencies / coordination:** BL-004, BL-008, BL-010, and later changes to
  About or Last Render provide migration opportunities.
- **Problem:** Several presentation-only controllers use substantial hand-built
  AppKit layout, especially About. Repeating that approach for Settings,
  onboarding, and diagnostics would increase UI maintenance cost.
- **Decision:** Do not perform a whole-app rewrite. Adopt SwiftUI incrementally
  for settings-style and content-heavy surfaces while retaining AppKit and
  WebKit where they directly support the app's menu bar and rendering behavior.

### Migration order

1. **New Settings window — highest priority.** Build the shared General,
   Rendering, and Shortcuts surface in SwiftUI when the trigger documented in
   `BACKLOG.md` is met. Keep the existing AppKit app lifecycle.
2. **New first-launch guide and renderer diagnostics — high priority.** Create
   these new, self-contained views in SwiftUI from the start rather than adding
   new hand-built constraint layouts.
3. **About window — medium priority.** Migrate when About next receives a
   functional or substantial design change. Preserve selectable release notes,
   Copy Version Info, build identification, project link, initial scroll
   position, localization, and Command-W behavior.
4. **Last Render action and zoom chrome — medium to low priority.** SwiftUI may
   host the controls, but retain the proven AppKit window and image scrolling
   implementation until SwiftUI can match its centering, fit, actual-size,
   tall-image, and pixel-boundary behavior without regressions.
5. **Clipboard menu preview — low priority.** Migrate only if a hosted SwiftUI
   view preserves fixed menu sizing, accessibility, and menu-open refresh
   behavior with less code than the current AppKit view.
6. **HUD content — lowest priority.** A SwiftUI-hosted label is optional, but
   keep the non-activating AppKit panel and screen-placement logic.

### Keep native AppKit/WebKit

- `NSStatusItem` and `NSMenu` application shell unless a later product design
  specifically benefits from a window-style menu bar extra.
- Carbon global-hot-key registration and conflict reporting.
- `NSPasteboard` clipboard reads, ownership checks, and PNG/TIFF writes.
- The hidden `WKWebView`, serialized JavaScript rendering, explicit sizing, and
  snapshot pipeline.
- AppKit window or panel shells when precise activation, focus, placement,
  scrolling, or close-shortcut behavior is required.

### Migration rules

- Introduce a small shared observable app-state/command layer before multiple
  SwiftUI surfaces need the same render, preview, or settings actions.
- Host SwiftUI inside the existing AppKit lifecycle; do not raise the macOS 14
  minimum or change menu bar lifetime merely to adopt a different UI framework.
- Migrate one surface at a time and keep a working app after every step.
- Preserve English and Simplified Chinese localization and keyboard access.
- Replace or extend tests before removing an AppKit implementation; verify the
  signed app as well as `make test`, `make app`, and `make run`.

### Reconsider a full rewrite only when

- most visible surfaces have already migrated successfully,
- the remaining AppKit shell causes measurable maintenance or product limits,
- the minimum supported macOS version provides native replacements for the
  required WebKit and menu bar behavior, and
- a tested migration plan preserves global shortcuts, clipboard safety,
  rendering determinism, window behavior, and release packaging.

## TD-002: Packaged render self-test

- **Priority:** P1
- **Effort:** M
- **Problem:** Release automation verifies architecture, signatures,
  notarization, stapling, and DMG integrity, but it does not prove that the
  executable inside `dist/md2png.app` can find its packaged resources and
  produce a real image.
- **Scope:** Add a noninteractive self-test entry point that runs from the built
  app bundle, loads the same bundled renderer used in production, renders one
  compact input containing Markdown, a GFM table, highlighted code, and
  Mermaid, validates a nonempty image and plausible dimensions, prints a
  concise result, and exits with a meaningful status. Add `make verify-dist`
  and require it in the guarded release workflow before publication.
- **Constraints:** Do not read or modify the user's clipboard, contact a
  network service, use source-tree fallback resources, or leave user content or
  temporary output behind. Exercise the production resource lookup and render
  queue rather than a parallel mock implementation.
- **Validation:** A normal packaged app passes; a missing or corrupt renderer
  bundle, missing Examples/resources, empty snapshot, wrong architecture, or
  renderer initialization failure produces a nonzero result. Keep the existing
  codesign, Gatekeeper, notarization, and DMG checks.
- **Coordination:** Share the underlying self-test runner with BL-010 so About
  can expose **Run Renderer Self-Test** without duplicating the test content or
  result model.

## TD-003: WebKit content-process recovery

- **Priority:** P2
- **Effort:** M
- **Problem:** The renderer handles navigation failures but does not recover
  when the WebKit content process terminates after initialization, which can
  leave later renders unavailable until the app restarts.
- **Scope:** Detect content-process termination, reload the bundled renderer,
  preserve the active request, and retry it at most once after initialization
  succeeds. Keep queued requests ordered and return a structured failure when
  recovery cannot complete.
- **Constraints:** Never complete a request twice, write duplicate clipboard
  output, retry indefinitely, discard Markdown, or fall back to network-loaded
  assets. A second termination for the same request must fail deterministically.
- **Validation:** Unit-test the recovery state machine and retry budget; cover
  termination while idle, during an active render, during reload, and with
  queued requests. Verify success writes one image and terminal failure
  preserves the source clipboard.
- **Coordination:** Integrate terminal recovery errors with BL-010 diagnostics
  and exercise the packaged recovery path through TD-002 where practical.

## TD-004: Accessibility and keyboard audit

- **Priority:** P2
- **Effort:** M
- **Problem:** Existing controls have partial accessibility coverage, while new
  onboarding, Settings, diagnostics, preview actions, zoom controls, and custom
  SwiftUI/AppKit bridges increase the risk of missing names, focus behavior,
  contrast, or standard keyboard commands.
- **Scope:** Audit the status menu, clipboard preview, HUD, About, Last Render,
  onboarding, Settings, and diagnostics with VoiceOver and Full Keyboard
  Access. Verify default and cancel buttons, logical focus order, Command-W,
  Command-Comma, Return, Escape, zoom shortcuts, shortcut conflict messaging,
  Increase Contrast, and Reduce Motion behavior.
- **Constraints:** Respect system accessibility settings instead of adding
  redundant app preferences. Keep non-activating HUD behavior and do not add
  Accessibility permission to the basic clipboard workflow.
- **Validation:** Record a compact manual matrix for English and Simplified
  Chinese, add automated checks for stable labels and shortcut routing where
  possible, and ensure every icon-only or custom control exposes a useful name,
  value, role, and enabled state.
- **Coordination:** Apply this audit to BL-001, BL-004, BL-008, BL-010, BL-012,
  and each SwiftUI migration step in TD-001.

## TD-005: Privacy-safe diagnostic logging

- **Priority:** P2
- **Effort:** M
- **Problem:** Transient HUD errors and copied version information do not leave
  enough evidence to diagnose intermittent renderer initialization, WebKit
  recovery, shortcut registration, clipboard-write, packaging, or resource
  lookup failures after they disappear.
- **Scope:** Introduce one structured diagnostic logger with stable categories
  for app lifecycle, renderer state transitions and durations, WebKit recovery,
  clipboard type/ownership outcomes, shortcut registration, bundled-resource
  lookup, and user-initiated Releases actions. Persist a small rolling log
  locally so a failure can be investigated after restart. Give each render a
  short random operation ID for correlating stages without identifying a user
  or device. Define a single redacted export model that BL-010 can expose as
  **Copy Diagnostic Logs** or **Save Diagnostic Logs…**, including app/build,
  macOS, architecture, and the selected recent time window.
- **Privacy constraints:** Never record Markdown or clipboard text, rendered
  image bytes, file contents, full user paths, pasteboard payloads, URLs with
  query strings, release response bodies, account/device identifiers, or raw
  error descriptions that may contain any of those values. Log only explicitly
  allowlisted metadata such as timestamps, category, stage, duration, result,
  error domain/code, clipboard type, and rendered pixel dimensions. Keep logs
  on-device, perform no telemetry or automatic upload, and require an explicit
  user action before copying, saving, or revealing them.
- **Retention and reliability:** Cap storage by both age and size, with an
  initial target of seven days and five one-megabyte files; delete the oldest
  entries first. Serialize writes off the main thread, tolerate an unavailable
  or unwritable log directory without affecting rendering, and avoid logging
  loops when the logger itself fails. Release and Debug builds must use the
  same schema, with verbose-only events disabled by default in Release.
- **Validation:** Use sensitive canary Markdown, clipboard text, file paths,
  URLs, and crafted errors to prove none appear in stored or exported logs.
  Cover concurrent render events, rotation by age and size, restart continuity,
  write failures, malformed prior files, and explicit export. Verify logging
  never changes the clipboard except for an explicit **Copy Diagnostic Logs**
  action, adds network traffic, delays rendering, or weakens the existing
  failure-preservation behavior.
- **Coordination:** Share error categories and operation IDs with BL-010, log
  packaged self-test stages from TD-002, and cover TD-003 recovery attempts and
  terminal failures. Include the export controls in the TD-004 accessibility
  audit and document the final storage path and deletion procedure in Privacy
  and Troubleshooting when this work ships.
