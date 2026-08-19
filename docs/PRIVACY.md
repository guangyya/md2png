# Privacy

md2png is local-first and its normal rendering path works offline after
installation.

## Clipboard access

The app accesses the clipboard only in response to visible user actions:

| Action | Clipboard behavior |
|---|---|
| Open the menu | Reads a short plain-text preview in memory |
| Render Clipboard as Image | Reads non-empty plain text; writes PNG and TIFF only after a successful render |
| Render Markdown File… | Reads one explicitly selected UTF-8 Markdown or plain-text file; unsupported extensions are disabled, and PNG/TIFF is written only after a successful render without reading the clipboard |
| Finder Open With | Reads one explicitly opened `.md` or `.markdown` file, uses the same local renderer, and opens Preview only after success without reading or writing the general clipboard |
| Finder Service | Reads the file paths Finder explicitly sends through **Services → Preview with md2png**, then applies the same local single-file checks and opens Preview without reading or writing the general clipboard |
| Bundled Example | Renders the explicitly selected bundled Markdown and opens Preview without reading or writing the general clipboard; Preview copies only on an explicit Copy action |
| Save as Split PNGs after a size-limit error | Uses the unchanged non-empty source from the failed render; writes numbered PNG files only to the folder explicitly selected by the user and does not write to the clipboard |
| Re-render Last Markdown | Reads the latest successful source from app memory; writes PNG and TIFF only after a successful render and any required clipboard confirmation |
| Restore Last Markdown | Writes the latest successful source after any required clipboard confirmation |
| Copy Version Info | Writes app version, source commit, build type, macOS version, and architecture as plain text |

If **Render Clipboard as Image** fails, the source Markdown remains on the
clipboard. If **Render Markdown File…** is cancelled, or a picker/Finder file
cannot be read, decoded, or rendered, the clipboard is unchanged. A Finder
Service request uses a separate system service pasteboard for its file paths;
it does not read the general clipboard. Successful Finder previews also leave
the clipboard unchanged until the user explicitly chooses Copy. The app keeps
no recent-file list, persistent access bookmark, file path, or directory monitor.
Bundled Examples never change the clipboard unless the user explicitly chooses
Copy in Preview. Clipboard contents are managed by macOS and can still be read
by other applications according to macOS clipboard behavior.

The most recent successful image and its source Markdown are retained only in
app memory for **Show Last Render**, **Re-render Last Markdown**, and **Restore
Last Markdown**. Both are discarded when the app quits. md2png does
not create a render history or silently save Markdown and images to files.
When another application changes the clipboard after md2png writes it, the Last
Markdown action requires confirmation before replacing that newer content.

Split export is an explicit Save-only recovery action offered after a size-limit
error. After the user chooses a parent folder, md2png creates one new output
folder and writes numbered PNGs locally. It does not add those images to the
clipboard, upload them, or retain a history. Existing export folders are not
overwritten.

Dragging from the Preview window is also an explicit local export. The app
creates one generation-isolated PNG in the system temporary directory only when
dragging starts, then offers its file URL and PNG bytes to the receiving app.
An unused cancelled export is removed immediately. An accepted export stays
available until md2png quits so receivers can finish reading it, then the app
removes its temporary export directory. Repeated drags of the same preview reuse
the same file. Dragging does not read or change the clipboard, upload the image,
or retain a render history.

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

## Local diagnostic logs

md2png keeps a small rolling diagnostic log on the Mac to help identify app
lifecycle, renderer, WebKit recovery, clipboard-type and ownership, shortcut,
bundled-resource, and user-initiated Releases failures. Log entries use a fixed,
typed schema and may contain timestamps, stages and outcomes, elapsed times,
image dimensions, aggregate counts, a random short render-operation ID, and
allowlisted error domains and numeric codes. They do not contain Markdown,
clipboard text or payloads, rendered bytes, file contents, full paths, URL query
strings, response bodies, device or account identifiers, or raw error messages.

Logs stay on the device under
`~/Library/Logs/md2png/Diagnostics`. Writes are serialized on a background queue,
files expire after 7 days, each file is limited to 1 MB, and at most 5 files are
kept. Logging failures do not interrupt rendering or change the clipboard. The
app does not upload, copy, save elsewhere, or reveal these logs automatically;
sharing diagnostics always requires a separate explicit user action.

In **About md2png → Diagnostics → Save Diagnostic Logs…**, the user explicitly
chooses the last hour, 24 hours, or 7 days and then chooses a destination with
the macOS save panel. The saved JSON contains the same allowlisted events plus
app/build, macOS, architecture, and the selected time interval. Saving does not
read or change the clipboard, contact a server, or upload the resulting file.
The user decides whether and how to share it.

Renderer failures cross the JavaScript-to-Swift boundary only as allowlisted
categories, a Mermaid diagram number, and a numeric Markdown line when
available. The details dialog never receives the raw Mermaid/WebKit message.
Only choosing **Copy Error Details** changes the clipboard; the copied text
contains the safe category, diagram/line or dimensions when relevant, a random
operation ID, and app/system versions. It contains no Markdown or raw error.

**About md2png → Diagnostics → Renderer Self-Test** renders a bundled input in
the same non-persistent local renderer and validates the resulting PNG. The
self-test implementation has no clipboard dependency and does not read or
change clipboard contents.

To delete all local diagnostics, quit md2png, choose **Go > Go to Folder…** in
Finder, enter `~/Library/Logs/md2png`, and delete the `Diagnostics` folder. The
folder is recreated only when a later diagnostic event is recorded.

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
