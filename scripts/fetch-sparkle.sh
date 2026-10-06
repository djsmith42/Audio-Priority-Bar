#!/usr/bin/env bash
# Downloads the pinned Sparkle release into Vendor/Sparkle, verifying its
# checksum, along with its signing tools. Does nothing when the pinned
# version is already in place. The app target runs this as its first build
# phase, so Xcode builds need no extra step.
set -euo pipefail

version="2.10.0"
sha256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
url="https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/Vendor/Sparkle"
stamp="$destination/.version"

if [[ -f "$stamp" && "$(cat "$stamp")" == "$version" && -d "$destination/Sparkle.framework" ]]; then
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

/usr/bin/curl -sSfL --retry 3 -o "$work/Sparkle.tar.xz" "$url"
actual="$(/usr/bin/shasum -a 256 "$work/Sparkle.tar.xz" | /usr/bin/awk '{print $1}')"
if [[ "$actual" != "$sha256" ]]; then
  echo "Sparkle $version checksum mismatch: expected $sha256, got $actual." >&2
  exit 1
fi

mkdir -p "$work/extract"
/usr/bin/tar -xf "$work/Sparkle.tar.xz" -C "$work/extract"
rm -rf "$destination"
mkdir -p "$destination"
# The framework to link and embed, and the tools that sign release archives.
/usr/bin/ditto "$work/extract/Sparkle.framework" "$destination/Sparkle.framework"
/usr/bin/ditto "$work/extract/bin" "$destination/bin"
cp "$work/extract/LICENSE" "$destination/LICENSE"
echo "$version" > "$stamp"
echo "Fetched Sparkle $version into $destination"
