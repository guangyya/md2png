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
export UPDATE_CHANNEL=stable
export BUNDLE_IDENTIFIER=io.github.OWNER.md2png
```

`GH_HOST` defaults to `github.com`, but `GH_REPO` is deliberately required for
publishing. `PROJECT_URL` is written to the packaged app only; if it is omitted
from a local build, About hides the project and Releases links.
`UPDATE_CHANNEL=stable` is an independent, explicit trust boundary for public
stable builds. Missing, unknown, `disabled`, and future values such as
`nightly` fail closed instead of inheriting the stable endpoint and artifact
policy.
`BUNDLE_IDENTIFIER` defaults to the personal value in `Info.plist`
and may be overridden for any build.
The build embeds the current Git commit in the packaged app automatically;
`SOURCE_COMMIT` may be supplied explicitly when building outside a Git checkout.

## One-time hosted release setup

The normal release path uses two separately scoped identities:

- Install a dedicated GitHub App only on this repository. Grant it repository
  metadata read, Contents write, and Pull requests write. Do not grant Actions,
  administration, environments, secrets, or Release publication permissions.
  Store its Client ID as the repository variable `RELEASE_PREP_CLIENT_ID` and
  its private key as the repository secret `RELEASE_PREP_PRIVATE_KEY`.
- Create the protected `release-signing` environment. Store
  `RELEASE_CERTIFICATE_P12_BASE64`, `RELEASE_CERTIFICATE_PASSWORD`,
  `RELEASE_SIGN_IDENTITY`, `RELEASE_CERTIFICATE_SHA256`, `APPLE_ID`,
  `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and
  `SPARKLE_EDDSA_PRIVATE_KEY` only in that environment.
  `RELEASE_SIGN_IDENTITY` is the complete Developer ID Application common name;
  the fingerprint is the certificate's SHA-256 value with or without colons.
  An environment reviewer is optional.

Sparkle uses a separate Ed25519 key; it does not require another Apple
certificate. Generate it once under the app-specific Keychain account, put only
the printed public key in `SUPublicEDKey`, and upload the exported private seed
to the protected environment without printing it:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.github.guangyya.md2png
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.github.guangyya.md2png \
  -x /path/to/temporary-private-key
gh secret set SPARKLE_EDDSA_PRIVATE_KEY \
  --repo "$GH_REPO" \
  --env release-signing \
  < /path/to/temporary-private-key
```

Securely remove the temporary plaintext export and keep one separately
encrypted offline recovery copy. The Keychain item, protected environment
secret, offline copy, and `SUPublicEDKey` must describe the same keypair.

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
reviewed fingerprint PR. Neither intermediate state is safe for publication:
the current sign and publish jobs do not compare their signer with the
repository-pinned verifier fingerprint, so the safety boundary is the operator's
maintenance-window freeze. Do not merge a Release PR or dispatch **Trusted
Release** while the secrets and repository pin disagree. Resume releases only
after `main` and all four environment secrets describe the replacement identity
and that agreement has been checked. A technical fail-closed boundary would
require a separate workflow change that makes sign and publish read and verify
the pin from protected `main` before publication.

The old private key may remain only as an encrypted offline recovery backup; it
cannot remain active in the same single-slot CI secrets. After a release signed
with the replacement is published and independently verified, remove the old
identity from active keychains and retain or destroy its encrypted backup
according to the operator's recovery policy. Do not revoke an old or expired
Developer ID certificate merely because it was rotated. Reserve revocation for
suspected compromise after assessing the effect on already published apps.

Treat Sparkle EdDSA rotation as a separate migration, not routine secret
replacement. The private key signs both the appcast and update ZIP, while the
matching public key is pinned in every installed app. Do not replace
`SPARKLE_EDDSA_PRIVATE_KEY` or `SUPublicEDKey` independently. A planned rotation
must first ship a bridge app signed by the old update key and containing the new
public key, preserve a feed path that remains verifiable by clients still on the
old key, and validate both cohorts before retiring the old key. The current
single `releases/latest/download/appcast.xml` feed does not implement that
dual-cohort migration, so rotation requires a reviewed infrastructure change.
If the update key may be compromised, stop seamless publication and direct
users to the notarized DMG; do not weaken `SURequireSignedFeed` or silently
replace the pin.

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
   moves both `Unreleased` sections to the same Asia/Shanghai release date. Its
   body also previews the closed `FEAT-*` and `TD-*` issues that will be grouped
   under the release milestone. The generated commit records the exact base and
   a SHA-256 digest of that reviewed plan.
4. Wait for normal CI and Release preflight, then merge the PR through the
   protected branch. The preparation workflow cannot approve or merge it.
5. Watch **Trusted Release** validate, sign, notarize, publish, verify the six
   assets, and update coverage history for that exact merge commit.

Release preflight derives the bump independently, requires the generated commit
to remain the single commit on its recorded base, recomputes the milestone plan
digest, rejects stale or unrelated edits, runs tests, and verifies an ad-hoc
release package without secrets or write permission. The publisher recomputes
the same reviewed issue set before any milestone mutation. Coverage is
deliberately not collected on the Release PR.
Generated Release PR labels are verified from the live pull-request API after
creation and again during preflight. A bounded retry covers the short period in
which an `opened` event can still expose an incomplete label snapshot; any PR
identity change or conflicting release label fails immediately.
The post-merge trusted Release build collects it once on Xcode 26.2. The two
stable CI jobs and Release preflight are hard publication gates; the explicitly
experimental Xcode preview job remains informational and cannot block a stable
release.

The trusted workflow isolates responsibilities:

- `validate` has read-only repository access, runs the full coverage-enabled
  test suite, and produces normalized JSON/Markdown coverage files;
- `sign` alone enters `release-signing`, imports the certificate into a
  temporary keychain, checks its identity, Team ID, and fingerprint, notarizes
  the exact source, signs the versioned ZIP and appcast with the Sparkle EdDSA
  key, and emits a one-day handoff with a SHA-256 manifest; and
- `publish` receives no Apple secret. It alone can create the annotated tag and
  Release, synchronize the release milestone, and update issue #42. It
  revalidates signatures, staples, metadata, manifest digests, asset digests,
  and the source commit, creates the Release as a draft, and makes it
  public/latest only after all six assets match and milestone synchronization
  succeeds.

The milestone synchronizer compares the previous stable tag with the exact
release commit. For each merged PR in that first-parent range, it includes
closed `FEAT-*` and `TD-*` issues referenced with GitHub closing keywords. It
also matches a leading identifier in the PR title, such as `FEAT-003`, so an
already completed issue remains discoverable even when it was closed manually.
It creates or reuses the exact `vX.Y.Z` milestone, rejects pull requests and any
extra, missing, or open issue in that milestone, and re-reads every planned issue
immediately before assignment so an intervening assignment to another milestone
fails closed. It ignores later same-identifier maintenance PRs for an issue
already shipped and performs a final exact membership check before closing the
milestone and making the draft Release public. That final read retries only
missing planned issues for a bounded period after successful assignments, to
cover GitHub collection-index lag. Extra, open, or pull-request items still fail
immediately and are never retried away. Historical Release PRs created
before milestone plan digests were introduced remain recoverable but do not
retroactively modify milestones.
Keep the issue identifier at the start of implementation PR titles and use a
closing reference such as `Closes #3` in the PR body whenever possible.
After publication, use `is:issue milestone:vX.Y.Z` in GitHub Issues to see the
complete version scope. Add `label:enhancement` for features or
`label:technical-debt` for internal work.

The workflow is serialized and non-canceling. A retry accepts an existing tag
only when it resolves to the same commit. Within the originating run, retrying
the failed publish job reuses the exact signed handoff, skips byte-identical
assets, and uploads only missing verified assets. A later manual recovery of a
draft that already has assets must name that originating Trusted Release run;
the workflow accepts exactly one unexpired handoff from the same repository,
release workflow, protected-main history, and release source, then revalidates
its manifest identity and every asset digest before publication. It never
re-signs a replacement for a partially populated draft. If
that exact version is already the latest published Release, the workflow skips
coverage generation, signing, and publication. A read-only macOS job instead
downloads the existing six assets and verifies their names, labels, sizes,
content types, SHA-256 digests, release notes, source metadata, signatures,
the Sparkle feed/archive EdDSA signatures, the repository-pinned public
leaf-certificate SHA-256 fingerprint,
notarization tickets, architecture, packaged self-test, and issue #42 links.
It has no environment secrets or repository write permission. The fingerprint
contains no private key or account credential and is independently observable
in every signed public app; update it through a reviewed infrastructure PR when
rotating the Developer ID certificate, before publishing with the replacement.
Any mismatch is rejected without replacing the tag, Release, assets, or
coverage entry. A draft with no uploaded assets may be resumed by dispatching
**Trusted Release** with only the exact 40-character commit already on `main`;
it cannot calculate or introduce another version.

If a generated Release PR is abandoned, close it and explicitly delete its
remote `codex/release-vX.Y.Z` branch. Confirm that neither an open Release PR nor
that remote branch remains before running **Prepare Release PR** again. When
`main` or either `Unreleased` section has changed, abandon the stale PR and
prepare a new one instead of updating previously reviewed release content in
place.

For a failed trusted run, first preserve the exact source commit and, if already
created, the annotated tag, draft Release, verified assets, and originating run
ID for diagnosis. For a transient publish failure, open that original run and
choose **Re-run failed jobs**. Do not start a new dispatch or re-run all jobs;
the failed-job retry preserves the original signed handoff and is the shortest
safe recovery path.

If the workflow itself needs repair, merge the reviewed fix first, then
dispatch **Trusted Release** from `main` with the same 40-character source
commit. When the matching draft already contains any asset, also enter the
originating run ID in `handoff_run_id`; the workflow downloads that exact
handoff instead of signing again. The run, workflow, repository, protected-main
ancestry, artifact name, expiry, manifest release identity, and file digests
must all match. If the artifact has expired or any binding differs, recovery
fails closed. When the matching draft has no assets, leave `handoff_run_id`
empty and a fresh signed handoff may be produced. After publication, the same
commit dispatch takes the read-only verification path and does not accept a
handoff run ID. Do not delete and recreate the tag or Release, overwrite an
asset, change the release commit, or merge another Release PR as a recovery
shortcut.

The protected-main workflow injects `MD2PNGUpdateChannel=stable` before signing,
including when a historical source predates the explicit channel build option.
Publication requires that exact marker for every contract-aware source. An
older signed handoff may omit it only when Git ancestry proves that its source
precedes the immutable channel-contract marker and the packaged App still
matches the canonical release identity, project URL, source commit, signature,
architecture, and non-Debug identity. Unknown or non-stable channel values are
always rejected.

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
  SPARKLE_EDDSA_PRIVATE_KEY="<private seed from secure storage>" \
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
then builds and notarizes the arm64 ZIP and DMG, generates and verifies the
signed appcast, creates and pushes the annotated version tag, and publishes six
assets using the matching changelog
section as the Release Notes:

The required asset membership, rendered names, labels, content types, and
local source paths are defined once in `scripts/release-assets.json` and
validated/rendered by `scripts/release-assets.mjs`. Release planning, both
publishers, handoff manifests, workflows, coverage history, and published
release verification consume that contract. Publishing authorization and
signing remain separate for the local and hosted paths.

- the versioned ZIP archive, labeled `md2png <version> — macOS app archive
  (Apple silicon)`;
- `appcast.xml`, whose feed signature and enclosure signature both verify with
  the public Ed25519 key pinned in `Info.plist`;
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

The script verifies all six asset names after publishing. It refuses an
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
  ".build/update-feed/appcast.xml#md2png ${version} — signed Sparkle appcast" \
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

When the packaged `MD2PNGUpdateChannel` is exactly `stable`, About derives this
feed URL from the packaged `PROJECT_URL`:

```text
https://github.com/OWNER/REPOSITORY/releases/latest/download/appcast.xml
```

Opening About never starts a request. **Check for Updates…** starts a Sparkle
information-only probe after a 60-second local cooldown. An on-latest result is
shown inline as **Up to Date**; newer-than-published and incompatible-system
results are distinguished from that success state. A valid newer item ends the
probe and About shows the signed feed's target metadata and bounded plain-text
release notes. **Download Update** starts Sparkle's user-initiated download,
validation, and preparation. Completion remains paused at **Ready to Install**
until the separate **Install and Relaunch** action. **Later** cancels the
prepared installer rather than creating an install-on-quit path. Automatic
checks, automatic downloads, and system-profile submission are disabled.

`Info.plist` is the version and trust-pin source. `CFBundleShortVersionString`
and `CFBundleVersion` must match the generated appcast's short version and
Sparkle version. `SUPublicEDKey` verifies both the signed feed and this immutable
archive URL:

```text
https://github.com/OWNER/REPOSITORY/releases/download/v${version}/md2png-${version}-macOS-arm64-developer-id.zip
```

The protected sign job authenticates the previously published appcast before
giving it to Sparkle's pinned `generate_appcast` tool. The newly signed feed
embeds non-empty notes, disables deltas, and retains at most three immutable
version entries plus a full-history link. Refusing to load or validate the
previous feed fails the release instead of silently truncating history (the
one-time `0.7.0` bridge is the only no-prior-feed exception). The handoff,
publisher, and published-release verifier require one to three uniquely
versioned items, exact current-release identity and immutable ZIP URL,
HTTPS-only links, a valid feed signature, and a valid current ZIP signature.
The ZIP also contains the existing Developer ID-signed, notarized app; the
versioned and latest DMGs remain manual installation and recovery artifacts.

Version `0.6.x` does not contain Sparkle, so upgrading from `0.6.x` to `0.7.0`
remains a manual DMG installation. Version `0.7.0` published the first valid
signed appcast and immutable ZIP; `0.7.0` to `0.8.0` is the first supported
seamless update path. Validate that path against a private test feed or isolated
repository before announcing `0.8.0`, without replacing a published release
asset.

Never mutate a published versioned ZIP. If an update is bad but its signing key
is still trusted, leave its evidence intact, stop marking it latest, and publish
a higher fixed version; Sparkle intentionally does not downgrade. If the feed,
key, or updater path cannot be trusted, stop seamless updates and direct users
to the notarized versioned DMG. Recovery must not disable signed-feed or
pre-extraction verification.

To review deterministic About layouts without contacting the feed, use a Debug
build with `UPDATE_CHANNEL=disabled` and a packaged fixture:

```sh
make run CONFIGURATION=debug \
  PROJECT_URL=https://github.com/guangyya/md2png \
  UPDATE_CHANNEL=disabled \
  TEST_UPDATE_VERSION=0.0.0 \
  TEST_UPDATE_STATE=seamless-update-available
```

Use `TEST_UPDATE_STATE=seamless-ready-to-install` to inspect the separate
install decision and its in-memory-state disclosure. Fixture actions are
disabled so these offline layouts cannot start an update or relaunch the app.

Both the Make target and release publisher reject test version/state overrides
for publication. Full install/relaunch validation must use a separately signed
test release and feed rather than changing or re-uploading a public asset.
