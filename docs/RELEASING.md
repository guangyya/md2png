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

## 1. Prepare the version

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

## 2. Create an ad-hoc arm64 build

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

## 3. Create a personal Apple Development build

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

## 4. Create a Developer ID build

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

## 5. Notarize and staple

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

## 6. Publish the GitHub release

The guarded path is:

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

It first runs the same `make coverage` command used by the canonical CI runner,
then builds and notarizes the arm64 ZIP and DMG, creates and pushes the annotated
version tag, and publishes five assets using the matching changelog section as
the Release Notes:

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

After publication, the least-privilege Coverage history workflow regenerates
the pinned [Test coverage history issue](https://github.com/guangyya/md2png/issues/42)
from all stable Release JSON assets. Its Markdown table is the accessibility and
rendering fallback for the Mermaid chart. The workflow has `issues: write` only;
pull-request coverage remains read-only. If the release event did not run it,
dispatch `Coverage history` manually after confirming the Release assets.

The equivalent manual fallback is below. Prefer `make publish-release`; the
manual path is useful only for diagnosing or recovering a partial publication.

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
