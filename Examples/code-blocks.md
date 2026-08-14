# Code review handoff

Use inline code for short values such as `Control-Command-X`, and fenced blocks
for snippets or structured data.

## Swift

```swift
guard let markdown = NSPasteboard.general.string(forType: .string),
      !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw AppError.emptyClipboard
}

renderer.render(markdown) { result in
    // Only a successful local render replaces the clipboard.
    handle(result)
}
```

## JSON

```json
{
  "displayName": "md2png",
  "architecture": "arm64",
  "rendering": "local-only",
  "automaticSend": false
}
```

## Shell

```sh
make test
make app CONFIGURATION=debug
make run CONFIGURATION=debug
```
