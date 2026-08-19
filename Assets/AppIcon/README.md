# App icon source

`AppIcon.png` is the approved high-resolution source for the md2png macOS app
icon. The build centers it at 824 × 824 pixels on a transparent 1024 × 1024
canvas before deriving the standard `.icns` sizes. That macOS-safe margin keeps
the icon's visible body aligned with other apps in the Dock while preserving
the full-bleed source for the README and website.

The visual was generated with OpenAI ImageGen in `logo-brand` mode, then its
flat chroma-key corners were removed locally to produce a transparent PNG. Its
three source lines, conversion arrow, and image frame represent the app's
local Markdown-to-image clipboard workflow.
