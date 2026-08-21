# Security policy

## Reporting a vulnerability

Please do not disclose a suspected vulnerability in a public issue. Use the
repository's private security advisory feature to contact the maintainer with:

- The affected version or commit.
- Steps to reproduce the issue.
- The expected security impact.
- Any suggested mitigation, if available.

The maintainer will acknowledge the report and coordinate a fix before public
disclosure.

## Security model

Markdown is sanitized before display, rendering uses a non-persistent local
`WKWebView`, raw Markdown HTML is disabled, and external Markdown images are
blocked. The application has no backend service, privileged updater helper,
analytics, or automatic chat action. Its About-only update discovery sends no
user content. A user-initiated in-app update lets Sparkle download only the
versioned HTTPS ZIP selected by the signed appcast, verify its EdDSA archive
signature and app code signature, and pause before the separate Install and
Relaunch decision. The Developer ID-signed, notarized, and stapled DMG remains
an explicit browser-based installation and recovery path. See
[Privacy](docs/PRIVACY.md) for clipboard and network behavior.
