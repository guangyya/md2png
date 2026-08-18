# Accessibility and keyboard audit

This checklist covers the native macOS surfaces targeted for md2png 0.10. The
basic clipboard workflow remains available without Accessibility permission.
The HUD remains nonactivating; status changes are announced through the menu bar
item instead of moving keyboard or VoiceOver focus.

## Automated evidence

The test suite checks stable accessibility roles, labels, values, enabled states,
announcement ownership, current user-configured shortcuts, default and cancel
actions, modeless window commands, Last Render zoom commands, shortcut conflict
feedback, Sample Guide focus movement, adaptive type layouts, Increase Contrast,
and Reduce Motion. English and Simplified Chinese bundles must contain the same
keys and compatible format arguments.

Run before the manual smoke test:

```sh
make test
make app
make run
```

## Manual release-candidate matrix

Run the complete matrix once with English and once with Simplified Chinese as
the preferred app language. Turn on VoiceOver and Keyboard navigation. Repeat
the Welcome and Sample Guide rows with Increase Contrast enabled and with Reduce
Motion enabled. A release candidate passes only when every box is checked.

| Surface | VoiceOver and focus order | Keyboard behavior | English | 简体中文 |
|---|---|---|:---:|:---:|
| Status menu and clipboard preview | Menu bar button announces the current render/update state; clipboard preview precedes actionable menu items; disabled commands are announced as unavailable. | Arrow keys traverse enabled items; Return activates; Escape closes; configured Render and Last Render equivalents match Settings. | [ ] | [ ] |
| HUD | Copy, render, restore, save, conflict, and error feedback is announced once; errors have higher priority; no window or focus is activated. | The current app keeps focus and receives the next keystroke. | [ ] | [ ] |
| Last Render | Rendered image announces its pixel dimensions; toolbar order is Copy, Save, Preview, Fit, Zoom Out, zoom value, Zoom In; zoom value explains that it resets to Actual Size. | Command-C, Command-S, Command-9, Command-0, Command-Minus, Command-Plus, Command-W, and Command-Comma work; Tab reaches toolbar controls. | [ ] | [ ] |
| About and diagnostics | Version copy, update status/actions, release notes, Diagnostics, and Done are distinct; update progress and failures are announced without duplicate HUD speech. | Tab follows visual order; Return activates Done/default alerts; Escape activates Cancel or Later; `Command-W` closes and `Command-,` opens Settings. | [ ] | [ ] |
| Welcome | Workflow is one concise description; replay is separate; shortcut rows announce current shortcut and Ready/Detected/Works/Unavailable; Launch at Login state and actions are explicit. | Tab visits Replay, Launch at Login, Try an Example, and Done; Return activates Done; `Command-R` replays; `Command-W` closes. | [ ] | [ ] |
| Sample Guide | Hidden examples are absent until revealed; focus begins on the first example; recommended and highlighted state is not color-only. | Tab/Shift-Tab and Up/Down move through examples; Return/Space activates; Escape closes. | [ ] | [ ] |
| Settings | Each recorder is an AXButton with command label, current shortcut value, and recording help; conflicts include text and leave menu fallbacks available; Restore Defaults reports completion. | Tab visits both recorders then Restore Defaults; Space/Return begins recording; Escape cancels recording; `Command-W` closes. | [ ] | [ ] |
| Confirmation and error alerts | Title, explanation, clipboard-preservation note, and buttons are read in order. | Return performs the default action; Escape performs Cancel/Later where present; Copy Error Details remains an explicit separate action. | [ ] | [ ] |

## Adaptive display checks

- With Reduce Motion on, Welcome shows the complete workflow without an
  autoplay sequence, Sample Guide reveals its destination without animated
  movement, and shortcut verification changes text/symbol/border without bounce
  or scale animation.
- With Increase Contrast on, shortcut keycaps, shortcut rows, replay controls,
  Sample Guide selection, and the recommended example use stronger borders or
  fills. Ready, detected, verified, conflict, selected, and disabled states also
  differ by text, symbol, trait, or enabled state rather than color alone.
- At an accessibility text size and on the smallest supported visible frame,
  Welcome and Sample Guide scroll instead of clipping actions.
