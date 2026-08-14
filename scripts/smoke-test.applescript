-- Developer-only smoke test. Run after `make run`; the terminal host must have
-- Accessibility permission because System Events sends the shortcut. The app's
-- normal user workflow does not require that permission.
set the clipboard to "# Smoke test" & return & return & "| A | B |" & return & "|---|---|" & return & "| 1 | 2 |"
tell application "System Events"
    keystroke "x" using {control down, command down}
end tell
delay 3
set clipboardInfo to clipboard info
return clipboardInfo
