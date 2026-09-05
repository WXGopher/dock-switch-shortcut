#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/dock-switcher-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc -swift-version 5 \
  "$repo_dir/native/DockModel.swift" \
  "$repo_dir/native/LegacyHelper.swift" \
  "$repo_dir/tests/native/main.swift" \
  -framework Cocoa -o "$test_dir/native-tests"
"$test_dir/native-tests"
