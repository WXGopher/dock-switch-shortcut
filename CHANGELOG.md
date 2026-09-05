# Changelog

## 0.2.0

- Run Dock Switcher as a standalone native macOS menu bar app, with no Raycast requirement.
- Add menu controls for enabling shortcuts, viewing the current mapping, Accessibility permission, and optional login startup.
- Keep shortcuts disabled on first launch and make URL control an explicit opt-in.
- Reduce the optional Raycast extension to app URL requests; disabling shortcuts now pauses the app instead of removing a helper.
- Build universal Apple Silicon and Intel app releases with GitHub Actions, packaged as DMG and ZIP downloads with checksums.
- Replace Raycast's duplicate Dock parser tests with URL allowlist and opening-failure tests.
- Add bilingual installation, migration, release-signing, and development guidance.

## 0.1.0

- Initial source release of Dock Switcher, including its Swift helper and icon.
- Add reproducible npm dependencies, build configuration, bilingual installation instructions, and checks.
- Create the LaunchAgents directory on first setup and handle paths without shell interpolation.
- Report service-unload failures before removing installation files.
- Parse Dock preferences as structured JSON so unusual app names do not break the mapping display.
- Return borrowed keyboard events without retaining them in the long-running helper.
- Preserve the original Command-number mapping, including interception of unmapped number keys.
