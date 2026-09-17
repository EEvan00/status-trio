<p align="center">
  <img src="screenshots/status-style.png" width="288" alt="Four Status Trio menu bar icon styles rendered from different settings">
</p>

# Status Trio

<p align="center">
  <img src="Support/AppIcon.svg" width="112" alt="Status Trio app icon">
</p>

<p align="center"><strong>Three system signals. One native macOS menu bar icon.</strong></p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="screenshots/normal.png" width="494" alt="Status Trio menu bar icon showing Wi-Fi, battery, and volume at a glance">
</p>

<p align="center">
  <img src="screenshots/popup.png" width="360" alt="Status Trio popover showing battery, Wi-Fi, and volume controls in the macOS menu bar">
</p>

Status Trio is a native macOS menubar app that combines Wi-Fi, battery, and volume into one compact, configurable menu bar icon. It is inspired by the iPhone Duo's combined status bar icon for Wi-Fi, Battery, and Cellular Data, adapted for Mac with Volume instead of Cellular Data.

> Status Trio is an independent project and is not affiliated with Apple.

## Highlights

- **One combined status icon** — keeps battery, Wi-Fi, and volume in a single menu bar item.
- **Configurable rendering** — choose an icon size from 16–36 pt, with 28 pt as the default.
- **Connection icon choices** — optionally use the standard Wi-Fi signal icon for Ethernet, Personal Hotspot, temporary connections, or Internet Sharing.
- **Detailed battery status** — percentage, charging bolt, estimated time to full, Low Power Mode, and a Battery Settings shortcut.
- **Optional MagSafe LED control** — open Battery details to leave the connector light under system control or keep it off. The privileged helper runs only when the setting changes or must be reapplied after a wake or power-source transition.
- **Wi-Fi awareness** — signal strength, current network name, and common connection states.
- **Volume at a glance** — output level and mute state, with controls available from the popover.
- **macOS-native controls** — left-click for a status popover and right-click for the standard menu.
- **Efficient updates** — event-driven monitoring with a low-frequency polling fallback.
- **Twelve languages** — follow the system language or choose one manually; changes apply immediately.
- **Launch at login** — optional startup with guidance when macOS requires approval.

## Requirements

- macOS 15 or later
- Swift 6 toolchain (Xcode 16 or later)

## Run from source

```bash
git clone https://github.com/404404/status-trio.git
cd status-trio
bash scripts/build-app.sh release
```

Wi-Fi names and scanning require location permission. Use the bundled app above: `swift run` launches a bare executable without the app’s privacy configuration.

## Build a local app

Build an ad-hoc-signed app bundle and launch it:

```bash
bash scripts/build-app.sh release
```

The bundle is created at `dist/StatusTrio.app`. To build without quitting or launching an existing instance, run:

```bash
bash scripts/build-app.sh release no-open
```

The ad-hoc-signed bundle is intended for local personal use. Gatekeeper may reject it if the bundle is transferred with quarantine metadata.

## Install a GitHub Release

Download the latest `StatusTrio-*.dmg` from the [GitHub Releases page](https://github.com/404404/status-trio/releases), open it, and copy `Status Trio.app` into `/Applications`.

The current public build is ad-hoc signed but is not notarized by Apple. macOS may show this warning on first launch:

> Apple cannot verify “Status Trio” is free of malware that may harm your Mac or compromise your privacy.

This is a Gatekeeper warning caused by the missing Developer ID signature and Apple notarization. It does not by itself mean the app contains malware. Only bypass the warning when the DMG was downloaded from the official GitHub Releases page and its published SHA-256 checksum matches.

After copying the app into `/Applications`, remove the quarantine attribute and open it:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Alternatively, try to open the app once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**.

Do not disable Gatekeeper globally. This fork currently ships GitHub Releases only; Sparkle automatic updates are disabled until the fork is configured with its own matching signing key pair.

## Usage

- **Left-click** the menu bar icon to open the status popover.
- **Right-click** it for the native menu, including version and quit actions.
- Open **Settings** to change the icon size, connection icon style, battery display options, language, update checks, and launch-at-login behavior.
- Enable the current Wi-Fi network name when prompted; macOS requests location access for this optional detail.

## Languages

Status Trio follows the macOS preferred language by default and includes English, Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German, Italian, Brazilian Portuguese, Russian, and Arabic.

## Privacy

Status Trio reads its regular status data through public macOS frameworks. It does not use App Sandbox or require a network entitlement, and it does not include telemetry or analytics. Location access is optional and requested only when you choose to display the current Wi-Fi network name.

MagSafe LED control is an optional exception: Apple does not provide a public API for it, so this feature uses the private AppleSMC `ACLC` key on supported hardware. Enabling the feature registers a narrowly scoped launch daemon through macOS Service Management and requires user approval. The helper accepts only `system` or `off`, reports whether the verified SMC write succeeded, exits after each event, and can be unregistered only after it returns the LED to system control.

## Development

Run the test suite:

```bash
swift test
```

Run a focused XCTest filter through the helper:

```bash
bash scripts/test.sh BatteryMonitorTests
```

To build a worktree app alongside the main installation:

```bash
bash scripts/build-worktree.sh release
```

The helper derives a development bundle identifier and display name from the current branch. Both values can be overridden:

```bash
BUNDLE_ID=io.github.404404.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

The single-instance lock is scoped by bundle identifier, so differently identified builds can run at the same time.

## Technical baseline

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` menu bar app
- Sparkle for update checks

## Documentation

- [Automated GitHub Actions releases](docs/github-actions-release.md)
- [Status Trio design specification](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [Menu bar icon SVG](status-menubar.svg)
- [Data-driven icon demo](status-menubar-demo.html)

## License

Copyright 2026 lingyired.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Author

Created and maintained by [lingyired](https://github.com/lingyired).<br>
Website: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
