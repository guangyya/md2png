# Weekly delivery update

Everything below is rendered locally on your Mac.

| Area | Status | Owner | Notes |
|:--|:--:|--:|:--|
| macOS app | ✅ Done | Alice | Ready to share |
| Documentation | 🚧 In progress | Bob | Release notes next |
| Validation | ⏳ Pending | Carol | Test on a second Mac |

```mermaid
flowchart LR
    Draft[Copy Markdown] --> Render[Render locally]
    Render --> Review{Looks good?}
    Review -->|Yes| Paste[Paste PNG]
    Review -->|No| Draft
    Paste --> Send[Send manually]
```

> md2png never sends a message automatically.
