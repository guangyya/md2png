# Releasing md2png

The repository supports local builds, Apple silicon ZIPs, installable DMGs, and
properly signed and notarized releases.

The user-visible app is `md2png.app`. Technical identifiers and artifact names
use ASCII (`MD2PNG` and `md2png`) so shell commands and automation remain
predictable.

Set the public repository and app identity for the packaging session. No
repository owner or path is embedded in source:

```sh
export GH_HOST=github.com
export GH_REPO=OWNER/REPOSITORY
export PROJECT_URL="https://${GH_HOST}/${GH_REPO}"
export BUNDLE_IDENTIFIER=io.github.OWNER.md2png
```

`GH_HOST` defaults to `github.com`, but `GH_REPO` is deliberately required for
publishing. `PROJECT_URL` is written to the packaged app only; if it is omitted
from a local build, About hides the project and Releases links.
`BUNDLE_IDENTIFIER` defaults to the personal value in `Info.plist`
and may be overridden for any build.
The build embeds the current Git commit in the packaged app automatically;
`SOURCE_COMMIT` may be supplied explicitly when building outside a Git checkout.

## One-time hosted release setup

The normal release path uses two separately scoped identities:

- Install a dedicated GitHub App only on this repository. Grant it repository
  metadata read, Contents write, and Pull requests write. Do not grant Actions,
  administration, environments, secrets, or Release publication permissions.
  Store its App ID and private key as repository secrets
  `RELEASE_PREP_APP_ID` and `RELEASE_PREP_PRIVATE_KEY`.
- Create the protected `release-signing` environment. Store
  `RELEASE_CERTIFICATE_P12_BASE64`, `RELEASE_CERTIFICATE_PASSWORD`,
  `RELEASE_SIGN_IDENTITY`, `RELEASE_CERTIFICATE_SHA256`, `APPLE_ID`,
  `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` only in that environment.
  `RELEASE_SIGN_IDENTITY` is the complete Developer ID Application common name;
  the fingerprint is the certificate's SHA-256 value with or without colons.
  An environment reviewer is optional.

Keep the `release`, `release:patch`, `release:minor`, and `release:major` labels.
Protect `main` and require the stable CI checks plus Release preflight. The App
token is minted only inside Prepare Release PR, is limited to this repository,
and is revoked by the pinned token action after the job.

### Credential expiry and rotation

Record the Developer ID Application certificate's expiry date and schedule its
replacement before the next release would cross that date. Normal expiry does
not invalidate apps that were validly timestamped while the certificate was
valid, but new releases require a current identity. Create the replacement
certificate for the same Team, export and locally validate its password-protected
PKCS#12 identity, and prepare and review the infrastructure PR that changes the
repository-pinned public leaf-certificate fingerprint.

The workflow has one set of certificate secrets and one pinned fingerprint, so
it does not support old and new signing identities in parallel. Before switching,
finish every in-flight release under the old identity, or explicitly abandon it
while preserving any evidence needed for diagnosis. Enter a maintenance window:
do not merge a Release PR or dispatch **Trusted Release** until the switch is
complete. During that window, replace the certificate, password, identity, and
fingerprint secrets together in `release-signing`, then merge the already
reviewed fingerprint PR. Either intermediate state is intentionally fail-closed;
never publish while the secrets and repository pin disagree. Resume releases
only after `main` and all four environment secrets describe the replacement
identity.

The old private key may remain only as an encrypted offline recovery backup; it
cannot remain active in the same single-slot CI secrets. After a release signed
with the replacement is published and independently verified, remove the old
identity from active keychains and retain or destroy its encrypted backup
according to the operator's recovery policy. Do not revoke an old or expired
Developer ID certificate merely because it was rotated. Reserve revocation for
suspected compromise after assessing the effect on already published apps.

Rotate the preparation GitHub App private key without changing its permissions
or repository selection. Generate a replacement key while the old key is still
valid, replace `RELEASE_PREP_PRIVATE_KEY`, and confirm the next planned
**Prepare Release PR** run can mint its short-lived token. Revoke the old App
key only after that run succeeds. If a key may have been exposed, revoke it
immediately, replace the repository secret, and audit App installation activity
before preparing another release.

## Normal hosted release

Maintain complete release notes under `Unreleased` in `CHANGELOG.md` and concise
in-app highlights under `Unreleased` in `ABOUT_CHANGELOG.md` as user-visible
changes merge. The preparation workflow never invents or summarizes notes.

To release:

1. Open **Actions → Prepare Release PR → Run workflow** on `main`.
2. Choose exactly `patch`, `minor`, or `major` once.
3. Review the generated `codex/release-vX.Y.Z` PR. It changes only `Info.plist`,
   `CHANGELOG.md`, and `ABOUT_CHANGELOG.md`, increments the build by one, and
   moves both `Unreleased` sections to the same Asia/Shanghai release date.
4. Wait for normal CI and Release preflight, then merge the PR through the
   protected branch. The preparation workflow cannot approve or merge it.
5. Watch **Trusted Release** validate, sign, notarize, publish, verify the five
   assets, and update coverage history for that exact merge commit.

Release preflight derives the bump independently, rejects stale or unrelated
edits, runs tests, and verifies an ad-hoc release package without secrets or
write permission. Coverage is deliberately not collected on the Release PR.
The post-merge trusted Release build collects it once on Xcode 26.2. The two
stable CI jobs and Release preflight are hard publication gates; the explicitly
experimental Xcode preview job remains informational and cannot block a stable
release.

The trusted workflow isolates responsibilities:

- `validate` has read-only repository access, runs the full coverage-enabled
  test suite, and produces normalized JSON/Markdown coverage files;
- `sign` alone enters `release-signing`, imports the certificate into a
  temporary keychain, checks its identity, Team ID, and fingerprint, notarizes
  the exact source, and emits a one-day handoff with a SHA-256 manifest; and
- `publish` receives no Apple secret. It alone can create the annotated tag and
  Release and update issue #42. It revalidates signatures, staples, metadata,
  manifest digests, asset digests, and the source commit, creates the Release as
  a draft, and makes it public/latest only after all five assets match.

The workflow is serialized and non-canceling. A retry accepts an existing tag
only when it resolves to the same commit. It resumes a matching draft by
skipping byte-identical assets and uploading only missing verified assets. If
that exact version is already the latest published Release, the workflow skips
coverage generation, signing, and publication. A read-only macOS job instead
downloads the existing five assets and verifies their names, labels, sizes,
content types, SHA-256 digests, release notes, source metadata, signatures,
the repository-pinned public leaf-certificate SHA-256 fingerprint,
notarization tickets, architecture, packaged self-test, and issue #42 links.
It has no environment secrets or repository write permission. The fingerprint
contains no private key or account credential and is independently observable
in every signed public app; update it through a reviewed infrastructure PR when
rotating the Developer ID certificate, before publishing with the replacement.
Any mismatch is rejected without replacing the tag, Release, assets, or
coverage entry. To resume a failed draft, dispatch **Trusted Release** with the
exact 40-character commit already on `main`; it cannot calculate or introduce
another version.

If a generated Release PR is abandoned, close it and explicitly delete its
remote `codex/release-vX.Y.Z` branch. Confirm that neither an open Release PR nor
that remote branch remains before running **Prepare Release PR** again. When
`main` or either `Unreleased` section has changed, abandon the stale PR and
prepare a new one instead of updating previously reviewed release content in
place.

For a failed trusted run, first preserve the exact source commit and, if already
created, the annotated tag, draft Release, and verified assets for diagnosis. A
transient failure can be retried without changing the workflow. If the workflow
itself needs repair, merge the reviewed fix first, then dispatch **Trusted
Release** from `main` with that same 40-character source commit. The publisher
resumes only a matching draft and never overwrites an existing asset; after
publication, the same dispatch takes the read-only verification path. Do not
delete and recreate the tag or Release, change the release commit, or merge
another Release PR as a recovery shortcut.

This read-only rerun proves that it cannot mutate publication state and that
the current remote snapshot remains internally valid. The pinned certificate
fingerprint independently anchors both app copies and the signed DMG container.
Coverage JSON is schema-validated against the exact release commit and its
Markdown is regenerated for byte comparison. GitHub's asset digest and the
downloaded bytes still live in the same mutable Release namespace, so this is
not an external provenance ledger against an already-authorized actor replacing
both metadata and content. That stronger threat model requires a separately
signed transparency record outside GitHub Releases and is not claimed here.

For a local dry run of deterministic preparation, use a disposable clean branch
or worktree:

```sh
make prepare-release BUMP=minor RELEASE_DATE=2026-08-15
```

The command changes release files only. It never commits, pushes, opens a PR,
signs, tags, or publishes.

## Emergency local recovery path

The hosted workflow is the normal publisher. The commands below remain the
operator-controlled fallback for diagnosing or recovering a release.

### 1. Prepare the version manually

`Info.plist` is the source of truth for the About window, artifact names, tag,
and GitHub Release title. Update both version keys:

- `CFBundleShortVersionString`: user-facing semantic version, such as `0.2.0`.
- `CFBundleVersion`: monotonically increasing build number, such as `2`.

Move the relevant entries from `Unreleased` into a dated section with exactly
the same semantic version in `CHANGELOG.md`. Add the matching version to
`ABOUT_CHANGELOG.md` using only short, one-line highlights, then run:

```sh
make test
make coverage
make verify-dist CONFIGURATION=release \
  PROJECT_URL="$PROJECT_URL" \
  BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER"
```

`verify-dist` verifies the app signature and arm64 executable, then invokes the
packaged executable's offline `--self-test` entry point. That test resolves only
resources inside `md2png.app`, renders Markdown, a GFM table, highlighted code,
and Mermaid through the production WebKit renderer, validates the in-memory PNG,
and leaves the clipboard and filesystem unchanged.

Commit the release preparation and push `main` before invoking the guarded
publisher. The publisher requires clean local `main` to exactly match
`origin/main`.

### 2. Create an ad-hoc arm64 build

```sh
make release PROJECT_URL="$PROJECT_URL" BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER"
make dmg PROJECT_URL="$PROJECT_URL" BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER"
```

The outputs are:

```text
dist/md2png-<version>-macOS-arm64.zip
dist/md2png-<version>-macOS-arm64.dmg
```

Both run on Apple silicon Macs only. Because the app is ad-hoc signed, another
Mac may warn that it cannot verify the developer. Do not present this as a
polished public release.

### 3. Create a personal Apple Development build

An `Apple Development` certificate is suitable for your own Mac and limited
development testing. It is not a substitute for Developer ID distribution and
cannot produce a broadly trusted notarized release.

Confirm the exact installed identity:

```sh
security find-identity -v -p codesigning
```

Then create clearly labeled artifacts:

```sh
make dmg \
  PROJECT_URL="$PROJECT_URL" \
  BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
  SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
  RELEASE_SUFFIX=apple-development
```

The outputs end in `-apple-development.zip` and
`-apple-development.dmg`, which avoids confusing them with a public release.

### 4. Create a Developer ID build

Join the Apple Developer Program and install a `Developer ID Application`
certificate in the login keychain. Then build with hardened runtime and a
trusted timestamp:

```sh
make dmg \
  PROJECT_URL="$PROJECT_URL" \
  BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  RELEASE_SUFFIX=developer-id
```

Verify the signature and architectures:

```sh
codesign --verify --deep --strict --verbose=2 "dist/md2png.app"
lipo -archs "dist/md2png.app/Contents/MacOS/md2png"
```

### 5. Notarize and staple

Store notarization credentials once. Use an app-specific password, not your
Apple ID password:

```sh
xcrun notarytool store-credentials MDPNGNotary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Then build, submit, staple, and recreate the ZIP and DMG. The workflow submits
the app archive first, staples the app, then signs, submits, and staples the
final DMG as its own distributable artifact:

```sh
make notarize \
  PROJECT_URL="$PROJECT_URL" \
  BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=MDPNGNotary \
  RELEASE_SUFFIX=developer-id
```

Final checks:

```sh
xcrun stapler validate "dist/md2png.app"
xcrun stapler validate "dist/md2png-<version>-macOS-arm64-developer-id.dmg"
spctl --assess --type execute --verbose=2 "dist/md2png.app"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "dist/md2png-<version>-macOS-arm64-developer-id.dmg"
```

### 6. Publish the GitHub release

The guarded emergency publisher is:

```sh
make publish-release \
  GH_HOST="$GH_HOST" \
  GH_REPO="$GH_REPO" \
  BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=MDPNGNotary
```

This command refuses to continue unless:

- the signing identity is a locally installed `Developer ID Application`;
- the current branch is a clean `main` matching `origin/main`;
- `CHANGELOG.md` contains a non-empty section matching the version in
  `Info.plist`;
- `ABOUT_CHANGELOG.md` contains concise highlights for that version so the app
  build can package them;
- `GH_REPO` is supplied in `OWNER/REPOSITORY` form and the selected GitHub host
  is authenticated;
- the version does not already have a GitHub Release.
- the packaged app passes signature, architecture, bundled-resource, and
  renderer self-tests.
- the normalized coverage JSON and Markdown summaries match the release version
  and exact commit.
- Xcode 26.2 is selected for the canonical coverage snapshot.

It first runs `make coverage` on the canonical Xcode 26.2 release toolchain,
then builds and notarizes the arm64 ZIP and DMG, creates and pushes the
annotated version tag, and publishes five assets using the matching changelog
section as the Release Notes:

- the versioned ZIP archive, labeled `md2png <version> — macOS app archive
  (Apple silicon)`;
- the versioned DMG, labeled `md2png <version> — macOS installer (Apple
  silicon)`;
- an identical `md2png-latest.dmg`, labeled `md2png — latest macOS
  installer (Apple silicon)`.
- `md2png-<version>-coverage.json`, the normalized machine-readable source-line
  coverage snapshot;
- `md2png-<version>-coverage.md`, the human-readable coverage summary.

The release is explicitly marked as the latest release, making this a stable
download URL across versions:

```text
${PROJECT_URL}/releases/latest/download/md2png-latest.dmg
```

The script verifies all five asset names after publishing. It refuses an
existing Release and validates the report schema, app version, and exact commit
before uploading. It also rechecks that coverage generation left the release
worktree clean, so rerunning a version cannot silently replace its coverage
record or package uncommitted renderer output. The GitHub CLI uses
the account authenticated for `GH_HOST`; no token is stored in the application.

After hosted publication, the originating trusted workflow directly regenerates
pinned issue [#42](https://github.com/guangyya/md2png/issues/42) from all stable
Release JSON assets. This is intentional because a Release created with the
job's `GITHUB_TOKEN` does not start another release workflow. The issue number
is fixed; renaming or closing it does not stop updates, while a missing issue or
damaged generated-section markers fail visibly. Its Markdown table is the
accessibility and rendering fallback for the Mermaid chart. A Release created
manually can also trigger the least-privilege Coverage history workflow; if it
does not, dispatch that workflow after verifying the Release assets.

The lower-level commands below are useful only for diagnosing or recovering a
partial local publication. Prefer the guarded helper within this emergency path.

Extract only the notes for the version being published:

```sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
mkdir -p .build
./scripts/release-notes.sh "$version" CHANGELOG.md \
  > ".build/release-notes-${version}.md"
```

Commit the version and changelog, then tag the exact release commit:

```sh
git tag -a "v${version}" -m "md2png ${version}"
git push origin main --follow-tags
```

Create a release and upload the notarized artifacts:

```sh
cp -f \
  "dist/md2png-${version}-macOS-arm64-developer-id.dmg" \
  "dist/md2png-latest.dmg"
gh release create "v${version}" \
  "dist/md2png-${version}-macOS-arm64-developer-id.zip#md2png ${version} — macOS app archive (Apple silicon)" \
  "dist/md2png-${version}-macOS-arm64-developer-id.dmg#md2png ${version} — macOS installer (Apple silicon)" \
  "dist/md2png-latest.dmg#md2png — latest macOS installer (Apple silicon)" \
  ".build/coverage/md2png-${version}-coverage.json#md2png ${version} — normalized source-line coverage (JSON)" \
  ".build/coverage/md2png-${version}-coverage.md#md2png ${version} — source-line coverage summary (Markdown)" \
  --title "md2png ${version}" \
  --notes-file ".build/release-notes-${version}.md" \
  --repo "${GH_HOST}/${GH_REPO}" \
  --verify-tag \
  --latest
```

Before announcing it, download the DMG on a second Mac and verify installation,
clipboard rendering, Mermaid, a GFM table, and manual paste into the target chat
application.

## In-app update contract

The update status in About uses the packaged `PROJECT_URL` to call the public
GitHub latest-release API without credentials. Successful responses are cached
for 24 hours; **Check Again** bypasses that cache while honoring a 60-second
minimum request interval and GitHub rate-limit retry headers. `Info.plist`
remains the single version source: `CFBundleShortVersionString` must match the
stable tag `v${version}`, the changelog section, and the version inside the
downloadable asset name:

```text
md2png-${version}-macOS-arm64-developer-id.dmg
```

The app requires that exact asset to have disk-image content type, positive size,
an HTTPS GitHub Release download URL, and a `sha256:` digest. The publishing script
checks those fields after creating the Release. Do not replace the versioned DMG
with only the `md2png-latest.dmg` alias; the updater deliberately uses immutable,
version-specific metadata.

The successful in-app flow shows the available version before any download.
Only **Download Update** downloads and verifies the DMG and asks macOS to open
it. Installation remains manual: the user drags md2png into Applications. There
is no embedded GitHub credential, privileged helper, silent replacement, or
automatic relaunch.

For a local end-to-end update test, keep the source version unchanged and run:

```sh
make run CONFIGURATION=debug \
  PROJECT_URL=https://github.com/guangyya/md2png \
  TEST_UPDATE_VERSION=0.0.0
```

The override changes only the packaged app before ad-hoc signing. The publish
target rejects it so it cannot alter a public release version.

To review deterministic About layouts without consuming a GitHub API request,
add one of `TEST_UPDATE_STATE=up-to-date`, `check-failed`, `download-failed`, or
`ready-to-install`
to that Debug `make run` command. The mock key is written only to the packaged
Debug app; both the Make target and release script reject it for publication.
The download-related mocks use the immutable published v0.1.0 asset metadata,
so retry actions exercise the real download and verification path. The
`ready-to-install` state requires that verified DMG in the update cache; when it
has been removed, the mock shows the recoverable download failure instead of a
ready action pointing at a missing file.
