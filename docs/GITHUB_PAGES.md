# GitHub Pages

The project website is a dependency-free static site in `site/`. The workflow
in `.github/workflows/pages.yml` publishes that directory whenever a site file
changes on `main`, and it can also be run manually.

## Enable the first deployment

1. Merge the site changes into `main` and push them to GitHub.
2. Open **Repository Settings → Pages**.
3. Under **Build and deployment**, choose **GitHub Actions** as the source.
4. Open **Actions → Deploy GitHub Pages** and run the workflow if the merge did
   not start it automatically.

The default project URL will be `https://guangyya.github.io/md2png/`.

## Add a custom domain

GitHub recommends verifying the domain before attaching it to a Pages site. In
personal **Settings → Pages**, add the domain and publish the TXT record GitHub
provides. Keep that TXT record after verification.

Then open **Repository Settings → Pages**, enter the hostname under **Custom
domain**, and save it before changing DNS.

### Subdomain, recommended for a project site

For a hostname such as `md2png.example.com`, add this DNS record:

| Type | Name | Value |
|---|---|---|
| CNAME | `md2png` | `guangyya.github.io` |

The target must not include `/md2png`.

### Apex domain

For a hostname such as `example.com`, use `ALIAS`/`ANAME` when the DNS provider
supports it, or add all four GitHub Pages IPv4 records:

```text
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

GitHub also recommends adding `www` as a CNAME to `guangyya.github.io` so it can
redirect between the apex and `www` variants.

Do not add wildcard DNS records. Once GitHub shows the DNS check as successful,
turn on **Enforce HTTPS**. DNS and certificate changes can take up to 24 hours.

This project deploys with a custom GitHub Actions workflow, so a checked-in
`CNAME` file is neither required nor used; GitHub stores the custom domain in
the Pages settings.
