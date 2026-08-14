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
user content, and the user-initiated download accepts only the expected
versioned HTTPS DMG, verifies its GitHub-provided size and SHA-256,
then relies on Developer ID signing, notarization, stapling, and macOS Gatekeeper
when opening it. See [Privacy](docs/PRIVACY.md) for clipboard and network behavior.
