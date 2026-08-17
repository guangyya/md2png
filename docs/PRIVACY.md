# Privacy

md2png is local-first and its normal rendering path works offline after
installation.

## Clipboard access

The app accesses the clipboard only in response to visible user actions:

| Action | Clipboard behavior |
|---|---|
| Open the menu | Reads a short plain-text preview in memory |
| Render Clipboard as Image | Reads non-empty plain text; writes PNG and TIFF only after a successful render |
| Re-render Last Markdown | Reads the latest successful source from app memory; writes PNG and TIFF only after a successful render and any required clipboard confirmation |
| Restore Last Markdown | Writes the latest successful source after any required clipboard confirmation |
| Choose an Example | Writes the selected bundled Markdown, then renders it and writes PNG/TIFF on success |
| Copy Version Info | Writes app version, source commit, build type, macOS version, and architecture as plain text |

If **Render Clipboard as Image** fails, the source Markdown remains on the
clipboard. If a bundled Example fails, that explicitly selected sample remains
on the clipboard instead. Clipboard contents are managed by macOS and can still
be read by other applications according to macOS clipboard behavior.

The most recent successful image and its source Markdown are retained only in
app memory for **Show Last Render**, **Re-render Last Markdown**, and **Restore
Last Markdown**. Both are discarded when the app quits. md2png does
not create a render history or silently save Markdown and images to files.
When another application changes the clipboard after md2png writes it, the Last
Markdown action requires confirmation before replacing that newer content.

## Local rendering

- Markdown is rendered in a non-persistent local `WKWebView`.
- Markdown parsing, sanitization, syntax highlighting, Mermaid, JavaScript, and
  CSS are bundled in the application.
- Raw HTML in Markdown is disabled, and rendered HTML is sanitized before the
  snapshot is taken.
- External Markdown images are replaced with a text placeholder rather than
  fetched. Rendered links are pixels in the PNG and are not navigated by the
  renderer.

## Data the app does not collect

- No Markdown or rendered image is uploaded.
- No analytics, telemetry, crash-reporting SDK, advertising SDK, or backend
  service is included.
- No chat-service login, API, bot, browser extension, or message injection is
  used.
- No message is pasted or sent automatically.
- No Accessibility permission is required for the basic workflow.
- No GitHub credential is embedded in the app.

## Network behavior

md2png makes no update request at launch, when About opens, on a background
timer, or during rendering. Only choosing **Check for Updates…** fetches the
public, signed `appcast.xml` from the latest GitHub Release. A 60-second local
cooldown prevents accidental repeated requests. Sparkle system-profile
submission and automatic checks/downloads are disabled. The request contains
the repository path and normal network metadata such as the source IP; it
contains no Markdown, rendered image, clipboard content, device identifier,
account data, GitHub credential, or Sparkle system profile.

If the signed feed reports no compatible newer version, About displays the
result inline. If an update exists, About shows its version and bounded
plain-text release notes. **Download Update** lets Sparkle download the exact
versioned Apple silicon ZIP from GitHub and verify both its EdDSA signature and
app code signature. The app pauses at **Ready to Install**; only the separate
**Install and Relaunch** choice replaces and restarts the app. **Later** cancels
the prepared install. macOS may request authorization when the installed
location is not writable. The notarized DMG remains a manual fallback and
recovery path.

**View Releases** is offered after an update failure and opens the browser only
when the user chooses it. **Open Project** in About also opens the configured
repository page when clicked. Rendering remains fully available offline.
