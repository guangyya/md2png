# Privacy

md2png is local-first and its normal rendering path works offline after
installation.

## Clipboard access

The app accesses the clipboard only in response to visible user actions:

| Action | Clipboard behavior |
|---|---|
| Open the menu | Reads a short plain-text preview in memory |
| Render Clipboard as Image | Reads non-empty plain text; writes PNG and TIFF only after a successful render |
| Choose an Example | Writes the selected bundled Markdown, then renders it and writes PNG/TIFF on success |
| Copy Version Info | Writes app version, build type, macOS version, and architecture as plain text |

If **Render Clipboard as Image** fails, the source Markdown remains on the
clipboard. If a bundled Example fails, that explicitly selected sample remains
on the clipboard instead. Clipboard contents are managed by macOS and can still
be read by other applications according to macOS clipboard behavior.

The most recent successful image is retained only in app memory for **Show Last
Render** and is discarded when the app quits. md2png does not create a render
history or silently save Markdown and images to files.

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
- No GitHub credential or release API client is embedded in the app.

## Network behavior

md2png makes no automatic update request and does not contact a Releases API.
Two explicit actions in About can ask macOS to open a web page in the default browser:

- **View All Releases…** first displays a confirmation, then opens the Releases page
  only when the user chooses **Open Releases**.
- **Open Project** in About opens the repository page when clicked.

Any browser traffic, authentication, or download after that point belongs to
the user's default browser. The app itself never downloads or installs an
update.
