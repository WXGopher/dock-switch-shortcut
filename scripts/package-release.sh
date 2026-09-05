#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)
release_tag=${1:-v$app_version}
if [ "$release_tag" != "v$app_version" ]; then
  echo "Release tag must match the app bundle version (v$app_version)." >&2
  exit 1
fi

sh scripts/build.sh universal
app='build/universal/Dock Switcher.app'
"$app/Contents/MacOS/dock-switcher" --help >/dev/null
version_output=$("$app/Contents/MacOS/dock-switcher" --version)
case "$version_output" in
  *" $app_version") ;;
  *) echo "Executable and bundle versions differ." >&2; exit 1 ;;
esac

export COPYFILE_DISABLE=1
export DITTONORSRC=1
mkdir -p release
stage_dir=$(mktemp -d "$repo_dir/build/release-stage.XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT HUP INT TERM
payload_dir="$stage_dir/payload"
mkdir -p "$payload_dir"
ditto --norsrc --noextattr --noqtn --noacl "$app" "$payload_dir/Dock Switcher.app"
for public_file in LICENSE README.md README.zh-CN.md; do
  cp -X "$public_file" "$payload_dir/$public_file"
done
mkdir -p "$payload_dir/media"
cp -X media/dock-shortcuts.svg "$payload_dir/media/dock-shortcuts.svg"
xattr -cr "$payload_dir"
chmod -RN "$payload_dir"
find "$payload_dir" -type d -exec chmod 755 {} +
find "$payload_dir" -type f -exec chmod 644 {} +
chmod 755 "$payload_dir/Dock Switcher.app/Contents/MacOS/dock-switcher"
# Normalize archive timestamps, and omit extended attributes and owner metadata.
find "$payload_dir" -exec touch -h -t 202001010000 {} +
if LC_ALL=C grep -raqF "$repo_dir" "$payload_dir" || \
   LC_ALL=C grep -raqE '/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|/private/var/folders/' "$payload_dir"; then
  echo "Refusing to package a machine-specific path." >&2
  exit 1
fi
codesign --verify --strict "$payload_dir/Dock Switcher.app"

asset_name="dock-switcher-$release_tag-macos-universal"
zip_file="$repo_dir/release/$asset_name.zip"
dmg_file="$repo_dir/release/$asset_name.dmg"
rm -f -- "$zip_file" "$dmg_file"
(
  cd "$payload_dir"
  /usr/bin/zip -X -q -r "$zip_file" .
)
unzip -tq "$zip_file"

ln -s /Applications "$payload_dir/Applications"
touch -h -t 202001010000 "$payload_dir/Applications"
hdiutil create -quiet -srcfolder "$payload_dir" -format UDZO -fs HFS+ \
  -volname 'Dock Switcher' -nospotlight -anyowners -srcowners off "$dmg_file"
hdiutil verify -quiet "$dmg_file"
xattr -c "$zip_file" "$dmg_file"
(
  cd release
  shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
echo "Release assets: release/$asset_name.dmg, release/$asset_name.zip, release/SHA256SUMS"
echo "The app is ad-hoc signed; it is not Developer ID signed or Apple-notarized."
