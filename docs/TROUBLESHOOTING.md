# Troubleshooting

## The app launches but no window appears

md2png is a menu bar accessory. It does not show a Dock icon or open a main
window at launch. Look for the md2png symbol in the macOS menu bar. If the menu
bar is crowded, check hidden menu bar items or temporarily quit another utility.

## A global shortcut does nothing

The default shortcuts are:

- Render: `Control-Command-X`
- Show Last Render: `Control-Command-Z`

Another utility can reserve the same system-wide combination. md2png shows a
local warning when registration fails; the equivalent menu bar commands remain
available. The app does not require Accessibility permission for these hotkeys.

## The clipboard is empty or is not recognized as Markdown

The render command expects non-empty plain text on the clipboard. Copy the
Markdown again, open the md2png menu to confirm its compact preview, then render.
Images, files, and rich content without a plain-text representation are not
treated as Markdown input.

## A Mermaid diagram does not render

Use a `mermaid` code fence. Do not use the diagram type as the fence language:

````markdown
```mermaid
flowchart LR
    A --> B
```
````

Flowcharts use node connections such as `A --> B`. Message syntax belongs to a
sequence diagram:

````markdown
```mermaid
sequenceDiagram
    Alice->>Bob: Request
    Bob-->>Alice: Response
```
````

For known-good inputs, choose **Examples → Flowchart**, **Sequence Diagram**, or
**Gantt Timeline** from the app. md2png uses the bundled Mermaid version and does
not load diagram plugins from the network.

## A code block has no expected highlighting

Add a recognized language after the opening fence, for example `swift`, `json`,
`python`, `javascript`, `typescript`, `sh`, `java`, `kotlin`, `cpp`, `go`, `rust`,
`sql`, `yaml`, `html`, or `css`. Unknown languages still render as code but may
use automatic or minimal highlighting.

## The result is too large

One render is limited to a logical size of 1600 × 16000 points. Shorten the
selection or split it into multiple messages. Very wide tables and diagrams can
also exceed the limit. Tall results that remain within the limit are scrollable
in Show Last Render.

## Show Last Render is blank or positioned oddly

First confirm that the success HUD appeared after rendering. **Show Last Render**
only becomes available after a successful render in the current app session.
Close the preview with `Command-W`, render again, and reopen it. Small images are
shown without upscaling; tall images fit the window width and begin at the top.

## macOS says the app cannot be opened or verified

Use a notarized DMG from the project Releases page when a public binary release
is available, not an ad-hoc or Apple Development build copied from another Mac.
The distributed app requires macOS 14 or newer and Apple silicon.

## Updating does not happen automatically

This is intentional. **View All Releases…** in About only confirms before opening
the Releases page; md2png never contacts an update API or downloads software. Quit the app,
download the newest DMG, and replace the existing copy in Applications.

## Information to include in a bug report

Open **About md2png** and use the copy icon beside the version. Include that
diagnostic line, the smallest Markdown input that reproduces the issue, and a
screenshot when appropriate. Remove confidential message content before filing
a report.
