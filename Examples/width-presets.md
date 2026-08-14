# Project Aurora — release snapshot

The desktop and mobile teams completed the offline rendering milestone and are
preparing a focused pilot. The remaining work covers package verification,
installation guidance, and final accessibility checks across supported macOS
versions. This same Markdown is rendered with every width preset so line
wrapping, table density, and overall image proportions can be compared directly.

## Delivery overview

| Workstream | Owner | Status | Target | Risk | Next action |
|:--|:--|:--:|:--:|:--:|:--|
| Native application | Alice | ✅ Done | Aug 12 | Low | Monitor pilot feedback |
| Local renderer | Bob | ✅ Done | Aug 13 | Low | Review regression samples |
| Accessibility | Carol | 🚧 Active | Aug 18 | Medium | Complete VoiceOver pass |
| Distribution | Diego | 🚧 Active | Aug 20 | Medium | Validate a clean installation |
| Documentation | Erin | ⏳ Pending | Aug 21 | Low | Publish the pilot guide |

## Pilot checklist

- [x] Markdown and rendered pixels remain on the Mac.
- [x] Failed renders preserve the source clipboard content.
- [x] Standard keeps the original output sizing.
- [ ] Validate Compact in a narrow chat conversation.
- [ ] Validate Wide with dense project status tables.

> **Decision requested:** confirm whether the pilot should default to Standard
> while allowing each user to keep their last explicit width selection.

## Notes

Use **Compact** for prose-heavy messages, **Standard** for the familiar balanced
layout, and **Wide** when a dense table benefits from fewer wrapped lines. The
app still leaves pasting, reviewing, and sending entirely to the user.
