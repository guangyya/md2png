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
blocked. The application has no backend service, embedded updater, analytics,
or automatic chat action. See [Privacy](docs/PRIVACY.md) for the clipboard and
network behavior.
