# GitHub Pages

The project website is a dependency-free static site generated from the shared
template in `site-src/index.html` and localized content under
`site-src/locales/`. Run `make site` to update the committed English and
Simplified Chinese routes in `site/`. The workflow in
`.github/workflows/pages.yml` verifies and publishes that directory whenever a
site source or output file changes on `main`, and it can also be run manually.

The public site is served at <https://md2png.wbxsh.com/> with HTTPS enforced.
The English page is canonical at `/`, and Simplified Chinese is available at
`/zh/`. Repository metadata should use the same public URL as its homepage.

## Deploy and verify changes

1. Update shared structure in `site-src/index.html` and localized copy in the
   matching JSON files under `site-src/locales/`. Keep the four feature groups
   synchronized in both locale files.
2. Run `make site`, then `make site-check`. Commit the generated
   `site/index.html` and `site/zh/index.html` with their sources.
3. Review both generated routes, including navigation, current feature claims,
   downloads, privacy claims, and update instructions.
4. Merge the site changes into `main`. A site source or output change starts
   **Deploy GitHub Pages**; the workflow can also be run manually.
5. Confirm the workflow's `github-pages` deployment succeeds.
6. Open <https://md2png.wbxsh.com/> and <https://md2png.wbxsh.com/zh/> over HTTPS
   and check the updated content and release download link.

## Custom-domain recovery

GitHub stores the active custom domain in Pages settings; this custom Actions
deployment does not require or use a checked-in `CNAME` file. If the domain is
detached, first confirm that `md2png.wbxsh.com` remains verified in personal
**Settings → Pages**, then restore it under **Repository Settings → Pages**.

The public site uses this DNS shape:

| Type | Name | Value |
|---|---|---|
| CNAME | `md2png` | `guangyya.github.io` |

The target must not include `/md2png`. Do not add wildcard DNS records. After
GitHub reports a successful DNS check, enable **Enforce HTTPS** and verify both
language URLs. DNS and certificate recovery can take up to 24 hours.
