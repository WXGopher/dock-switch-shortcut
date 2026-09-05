#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
sh scripts/build.sh all

host_arch=$(uname -m)
case "$host_arch" in
  arm64|x86_64) ;;
  *) echo "Unsupported host architecture: $host_arch" >&2; exit 1 ;;
esac

expected_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)
for app_arch in "$host_arch" universal; do
  binary="build/$app_arch/Dock Switcher.app/Contents/MacOS/dock-switcher"
  "$binary" --help >/dev/null
  version_output=$("$binary" --version)
  case "$version_output" in
    *" $expected_version") ;;
    *) echo "Executable and bundle versions differ." >&2; exit 1 ;;
  esac
  echo "Help and version checks passed: $app_arch ($version_output)"
done

xcrun lipo 'build/universal/Dock Switcher.app/Contents/MacOS/dock-switcher' \
  -verify_arch arm64 x86_64
