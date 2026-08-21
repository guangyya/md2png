# Accessibility and keyboard audit

This checklist covers every native macOS surface in md2png 0.13.3 and later.
The basic clipboard workflow remains available without Accessibility
permission. The HUD remains nonactivating and, while VoiceOver is running,
keeps one uninterrupted status message available long enough to finish speaking
without taking keyboard focus from the current app.

The checklist was refreshed on 2026-08-21 after Preview, Finder file entry
points, split export completion, PNG rounded corners, and the expanded Settings
window shipped. The last complete manual pass was performed on 2026-08-18 for
the 0.10 development build; every unchecked cell below must be completed again
before the next release candidate is approved.

## Automated evidence

The test suite checks stable accessibility roles, labels, values, enabled
states, announcement ownership, current user-configured shortcuts, default and
cancel actions, modeless window commands, Preview zoom commands, shortcut
conflict feedback, Sample Guide focus movement, adaptive type layouts, Increase
Contrast, and Reduce Motion. It also verifies clipboard preservation across
clipboard, picker, Finder, Example, failure, and split-export paths; transparent
rounded-corner output; and matching English and Simplified Chinese localization
keys and format arguments.

Run before the manual matrix:

```sh
make test
make app
make run
```

## Manual release-candidate matrix

Run the complete matrix once with English and once with Simplified Chinese as
the preferred app language. Enable VoiceOver and Keyboard navigation. Repeat
Welcome, Sample Guide, Settings, Preview, and alert checks with Increase
Contrast and Reduce Motion enabled. A release candidate passes only when every
box is checked and the date/version below are updated.

Manual pass: pending for the next release candidate.

| Surface | VoiceOver and focus order | Keyboard behavior | English | 简体中文 |
|---|---|---|:---:|:---:|
| Status menu and clipboard preview | The status item announces render/update state; the read-only clipboard preview precedes commands; disabled commands are announced as unavailable; Theme, Output Width, and Examples submenus expose their current state. | Arrow keys traverse enabled items; Return activates; Escape closes; configured Render and Show Last Render equivalents match Settings. | [ ] | [ ] |
| HUD | Copy, render, restore, save, shortcut-conflict, update, and error feedback is spoken once; the complete message remains available long enough to finish; the HUD never takes focus. | The current app keeps focus and receives the next keystroke. | [ ] | [ ] |
| Preview | The image announces pixel dimensions; the toolbar order is Copy, Save, Open in Preview, Fit, Actual Size, Zoom Out, zoom value, and Zoom In; rounded output has a visible non-color-only boundary. | Command-C, Command-S, Command-9, Command-0, Command-Minus, Command-Plus, Command-W, and Command-Comma work; Tab reaches every toolbar control; a drag can be cancelled without changing the clipboard. | [ ] | [ ] |
| Markdown file picker and Finder entry points | The picker describes supported file types; Open With and Services failures identify unsupported, unreadable, non-UTF-8, empty, or oversized input without exposing content. A successful Finder render moves focus to Preview. | Cancel closes the picker without changing the clipboard; one supported file opens through the picker, Finder Open With, and Services; unsupported selections remain disabled or fail safely. | [ ] | [ ] |
| Split PNG recovery | The size-limit alert explains that the clipboard is unchanged; the destination panel announces the exact part count; completion announces the saved count, folder, Show in Finder, and Done. | Escape cancels each stage; Return follows the visible default; Show in Finder selects every exported PNG; no stage writes to the clipboard. | [ ] | [ ] |
| Settings | General, PNG Output, and Keyboard Shortcuts are announced as distinct sections. Launch at Login exposes effective state and approval requirements; Rounded Corners exposes On/Off; each shortcut recorder announces its command, current value, and recording help. | Tab follows visual order; Space/Return toggles settings or begins recording; Escape cancels recording; Restore Defaults affects shortcuts only; Command-W closes. | [ ] | [ ] |
| About, diagnostics, and updates | Version copy, update status/actions, release notes, Diagnostics, and Done are distinct. Download, verification, Ready to Install, cancellation, success, and failure are announced without duplicate HUD speech. | Tab follows visual order; Return activates default actions; Escape activates Cancel or Later; Command-W closes and Command-Comma opens Settings. | [ ] | [ ] |
| Welcome | The workflow is one concise description; Replay is separate; shortcut rows announce current shortcut and Ready/Detected/Works/Unavailable; Launch at Login state and actions are explicit. | Tab visits Replay, Launch at Login or Open Settings, Try an Example, and Done; Return activates Done; Command-R replays; Command-W closes. | [ ] | [ ] |
| Sample Guide | Hidden examples are absent until revealed; focus begins on the first example; recommended and highlighted state is not color-only; selection explains that the result opens in Preview without changing the clipboard. | Tab/Shift-Tab and Up/Down move through examples; Return/Space activates; Escape closes. | [ ] | [ ] |
| Confirmation and error alerts | Title, explanation, clipboard-preservation note, and buttons are read in order. Renderer details identify safe diagram/line context without reading raw Markdown or parser text. | Return performs the default action; Escape performs Cancel, Done, or Later; Copy Error Details remains an explicit separate action. | [ ] | [ ] |

## Adaptive display checks

- With Reduce Motion on, Welcome shows the complete workflow without autoplay,
  Sample Guide reveals its destination without animated movement, and shortcut
  verification changes text, symbol, or border without bounce or scale motion.
- With Increase Contrast on, shortcut keycaps, rows, Preview image boundaries,
  rounded transparent corners, Sample Guide selection, and the recommended
  example use stronger borders or fills. Ready, detected, verified, conflict,
  selected, disabled, and On/Off states also differ by text, symbol, trait, or
  enabled state rather than color alone.
- At an accessibility text size and on the smallest supported visible frame,
  Welcome, Sample Guide, Settings, About, and alerts scroll or grow without
  clipping their primary and cancel actions.
- On a Retina and a non-Retina display, Preview's Actual Size description and
  reported PNG dimensions remain accurate at every output width.
