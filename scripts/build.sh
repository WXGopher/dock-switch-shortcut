#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

if [ "$(uname -s)" != Darwin ]; then
  echo "Building Dock Switcher requires macOS and Xcode Command Line Tools." >&2
  exit 1
fi

build_target=${1:-all}
case "$build_target" in
  arm64|x86_64|universal|all) ;;
  *) echo "Usage: sh scripts/build.sh [arm64|x86_64|universal|all]" >&2; exit 2 ;;
esac

export COPYFILE_DISABLE=1
export DITTONORSRC=1
mkdir -p build/resources/DockSwitcher.iconset

# Convert only the checked-in public icon; never copy machine-specific resources.
iconset=build/resources/DockSwitcher.iconset
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" assets/command-icon.png \
    --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" assets/command-icon.png \
    --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o build/resources/DockSwitcher.icns

make_bundle() {
  bundle_dir="build/$1/Dock Switcher.app"
  rm -rf -- "$bundle_dir"
  mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
  cp -X native/Info.plist "$bundle_dir/Contents/Info.plist"
  cp -X build/resources/DockSwitcher.icns "$bundle_dir/Contents/Resources/DockSwitcher.icns"
  plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null
}

finish_bundle() {
  bundle_dir="build/$1/Dock Switcher.app"
  binary="$bundle_dir/Contents/MacOS/dock-switcher"
  if [ "$1" != universal ]; then
    xcrun strip -S -x "$binary"
  fi
  # Fail without printing any private path if the compiler embeds checkout paths.
  if LC_ALL=C grep -aqF "$repo_dir" "$binary" || \
     LC_ALL=C grep -aqE '/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|/private/var/folders/' "$binary"; then
    echo "Refusing a binary containing a machine-specific build path." >&2
    exit 1
  fi
  xattr -cr "$bundle_dir"
  codesign --force --sign - --identifier io.github.wxgopher.DockSwitcher \
    --timestamp=none "$bundle_dir" 2>/dev/null
  codesign --verify --strict "$bundle_dir"
  echo "Built: $bundle_dir (macOS 13+)"
}

build_arch() {
  target_arch=$1
  make_bundle "$target_arch"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -gnone \
    -target "${target_arch}-apple-macosx13.0" \
    -module-name DockSwitcher \
    -file-prefix-map "$repo_dir=." -debug-prefix-map "$repo_dir=." \
    native/*.swift \
    -o "build/$target_arch/Dock Switcher.app/Contents/MacOS/dock-switcher" \
    -framework Cocoa -framework ApplicationServices -framework ServiceManagement
  finish_bundle "$target_arch"
}

case "$build_target" in
  arm64|x86_64) build_arch "$build_target" ;;
  universal|all)
    build_arch arm64
    build_arch x86_64
    make_bundle universal
    xcrun lipo -create \
      "build/arm64/Dock Switcher.app/Contents/MacOS/dock-switcher" \
      "build/x86_64/Dock Switcher.app/Contents/MacOS/dock-switcher" \
      -output "build/universal/Dock Switcher.app/Contents/MacOS/dock-switcher"
    finish_bundle universal
    xcrun lipo 'build/universal/Dock Switcher.app/Contents/MacOS/dock-switcher' \
      -verify_arch arm64 x86_64
    ;;
esac
