#!/bin/bash
set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$repo_root"

node_binary="${NODE:-node}"
release_assets_script="${RELEASE_ASSETS_SCRIPT:-scripts/release-assets.mjs}"
appcast_validator="${SPARKLE_APPCAST_SCRIPT:-scripts/sparkle-appcast.mjs}"
repository="${GH_REPO:-}"
project_url="${PROJECT_URL:-}"
private_key="${SPARKLE_EDDSA_PRIVATE_KEY:-}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Info.plist)"
generate_appcast="${SPARKLE_GENERATE_APPCAST:-.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
asset_contract="$($node_binary "$release_assets_script" json --version "$version")"
release_zip="$(jq -er '.assets[] | select(.key == "releaseZip") | .sourcePath' <<< "$asset_contract")"
appcast="$(jq -er '.assets[] | select(.key == "appcast") | .sourcePath' <<< "$asset_contract")"

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GH_REPO is required in OWNER/REPOSITORY form." >&2
  exit 1
fi
if [[ "$project_url" != "https://github.com/${repository}" ]]; then
  echo "PROJECT_URL must identify GH_REPO on GitHub." >&2
  exit 1
fi
if [[ -z "$private_key" ]]; then
  echo "SPARKLE_EDDSA_PRIVATE_KEY is required." >&2
  exit 1
fi
if [[ ! -x "$generate_appcast" ]]; then
  echo "Sparkle generate_appcast was not found at $generate_appcast." >&2
  exit 1
fi
test -s "$release_zip"

staging_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

previous_appcast="$staging_dir/appcast.xml"
previous_appcast_url="${project_url}/releases/latest/download/appcast.xml"
if /usr/bin/curl \
  --fail \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --silent \
  --show-error \
  --output "$previous_appcast" \
  "$previous_appcast_url"; then
  "$node_binary" "$appcast_validator" validate-feed \
    --file "$previous_appcast" \
    --public-key "$public_key"
elif [[ "$version" = "0.7.0" ]]; then
  rm -f "$previous_appcast"
else
  echo "The previous signed appcast could not be loaded; refusing to truncate update history." >&2
  exit 1
fi

archive_name="$(basename "$release_zip")"
archive_basename="${archive_name%.zip}"
cp "$release_zip" "$staging_dir/$archive_name"
./scripts/release-notes.sh "$version" CHANGELOG.md > "$staging_dir/${archive_basename}.md"
test -s "$staging_dir/${archive_basename}.md"
mkdir -p "$(dirname "$appcast")"

printf '%s' "$private_key" | "$generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/${repository}/releases/download/v${version}/" \
  --embed-release-notes \
  --maximum-versions 3 \
  --maximum-deltas 0 \
  --full-release-notes-url "${project_url}/releases" \
  --link "${project_url}/releases/tag/v${version}" \
  -o "$appcast" \
  "$staging_dir"

"$node_binary" "$appcast_validator" validate \
  --file "$appcast" \
  --archive "$release_zip" \
  --version "$version" \
  --build "$build" \
  --repository "$repository" \
  --public-key "$public_key"
