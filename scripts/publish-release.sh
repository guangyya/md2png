#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-md2pngNotary}"
gh_host="${GH_HOST:-github.com}"
gh_repo="${GH_REPO:-}"
project_url="${PROJECT_URL:-}"
bundle_identifier="${BUNDLE_IDENTIFIER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
tag="v${version}"
artifact_base="md2png-${version}-macOS-arm64-developer-id"
release_zip="dist/${artifact_base}.zip"
release_dmg="dist/${artifact_base}.dmg"
latest_dmg="dist/md2png-latest.dmg"
notes_file=".build/release-notes-${version}.md"

if [[ ! "$gh_host" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "GH_HOST must be a hostname such as github.com." >&2
  exit 1
fi

if [[ ! "$gh_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GH_REPO is required in OWNER/REPOSITORY form." >&2
  exit 1
fi

repo_ref="${gh_host}/${gh_repo}"
if [[ -z "$project_url" ]]; then
  project_url="https://${repo_ref}"
fi
project_url="${project_url%/}"

if [[ ! "$project_url" =~ ^https://[^/?#]+/[^/?#]+/[^/?#]+$ ]]; then
  echo "PROJECT_URL must be an HTTPS repository URL without a query or fragment." >&2
  exit 1
fi

if [[ "$sign_identity" != "Developer ID Application:"* ]]; then
  echo "SIGN_IDENTITY must be a Developer ID Application identity." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${sign_identity}\""; then
  echo "The requested Developer ID Application identity is not installed." >&2
  exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Release publishing must run from main." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit all changes before publishing a release." >&2
  exit 1
fi

git fetch origin main --tags
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Local main must exactly match origin/main." >&2
  exit 1
fi

mkdir -p .build
if ! ./scripts/release-notes.sh "$version" CHANGELOG.md > "$notes_file"; then
  echo "CHANGELOG.md has no section for ${version}." >&2
  exit 1
fi
if [[ ! -s "$notes_file" ]]; then
  echo "Release notes for ${version} are empty." >&2
  exit 1
fi

gh auth status --hostname "$gh_host" >/dev/null
existing_release_tags="$(
  gh release list --repo "$repo_ref" --limit 100 --json tagName --jq '.[].tagName'
)"
if grep -Fxq "$tag" <<< "$existing_release_tags"; then
  echo "Release ${tag} already exists." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
  && [[ "$(git rev-list -n 1 "$tag")" != "$(git rev-parse HEAD)" ]]; then
  echo "Existing tag ${tag} does not point to HEAD." >&2
  exit 1
fi

make notarize \
  SIGN_IDENTITY="$sign_identity" \
  NOTARY_PROFILE="$notary_profile" \
  PROJECT_URL="$project_url" \
  BUNDLE_IDENTIFIER="$bundle_identifier" \
  RELEASE_SUFFIX=developer-id

for artifact in "$release_zip" "$release_dmg"; do
  if [[ ! -s "$artifact" ]]; then
    echo "Expected release artifact is missing or empty: ${artifact}" >&2
    exit 1
  fi
done

cp -f "$release_dmg" "$latest_dmg"
if ! cmp -s "$release_dmg" "$latest_dmg"; then
  echo "The stable DMG alias does not match the versioned DMG." >&2
  exit 1
fi

if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  git tag -a "$tag" -m "md2png ${version}"
fi

git push origin "$tag"
gh release create "$tag" \
  "${release_zip}#md2png ${version} — macOS app archive (Apple silicon)" \
  "${release_dmg}#md2png ${version} — macOS installer (Apple silicon)" \
  "${latest_dmg}#md2png — latest macOS installer (Apple silicon)" \
  --repo "$repo_ref" \
  --title "md2png ${version}" \
  --notes-file "$notes_file" \
  --verify-tag \
  --latest \
  --fail-on-no-commits

uploaded_assets="$(
  gh release view "$tag" --repo "$repo_ref" --json assets --jq '.assets[].name'
)"
expected_assets=(
  "$(basename "$release_zip")"
  "$(basename "$release_dmg")"
  "$(basename "$latest_dmg")"
)
for expected_asset in "${expected_assets[@]}"; do
  if ! grep -Fxq "$expected_asset" <<< "$uploaded_assets"; then
    echo "Published release is missing asset: ${expected_asset}" >&2
    exit 1
  fi
done

release_url="$(gh release view "$tag" --repo "$repo_ref" --json url --jq .url)"
stable_dmg_url="${project_url}/releases/latest/download/$(basename "$latest_dmg")"
printf 'Release: %s\nLatest DMG: %s\n' "$release_url" "$stable_dmg_url"
