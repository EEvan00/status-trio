# MagSafe LED Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent System/Off MagSafe indicator switch to a Battery secondary panel.

**Architecture:** A testable app controller persists intent and writes a two-value configuration file. A launchd WatchPaths helper validates that file, writes only AppleSMC `ACLC`, and exits; the app reapplies Off on existing battery/wake events without polling.

**Tech Stack:** Swift 6, SwiftUI, AppKit, IOKit, launchd, SwiftPM, XCTest

**Spec:** `docs/superpowers/specs/2026-09-17-magsafe-led-control-design.md`

## Global Constraints

- macOS 15 minimum; CI acceptance uses Xcode 16.4 and Swift 6.1.2.
- No `isolated deinit`, Swift 6.2-only syntax, or third-party dependency.
- Helper writes only `ACLC = 0` or `ACLC = 1`.
- No polling; event-driven reapplication only.
- Do not commit, push, or publish without explicit user approval.

---

### Task 1: App-side state and persistence

**Files:**
- Create: `Sources/StatusTrioCore/MagSafe/MagSafeLEDController.swift`
- Test: `Tests/StatusTrioCoreTests/MagSafeLEDControllerTests.swift`

**Interfaces:**
- Produces: `MagSafeLEDMode`, `MagSafeLEDState`, `MagSafeLEDControlling`, and `MagSafeLEDController`.
- The controller persists a Boolean preference, exposes install/support/error state, atomically writes `system\n` or `off\n`, and reapplies only Off.

- [ ] Write tests proving default System mode, persistence, exact command payloads, rejection on write failure, and Off-only event reapplication.
- [ ] Run the focused test and confirm the missing production API causes failure.
- [ ] Implement the minimal controller and injected filesystem/helper boundaries.
- [ ] Run the focused test and confirm it passes.

### Task 2: Narrow AppleSMC helper and installer

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MagSafeSMC/include/SMCParamStruct.h`
- Create: `Sources/MagSafeSMC/MagSafeSMC.swift`
- Create: `Sources/StatusTrioMagSafeHelper/main.swift`
- Create: `Support/com.status-trio.magsafe-helper.plist`
- Create: `Support/install-magsafe-helper.sh`
- Modify: `NOTICE`

**Interfaces:**
- `MagSafeSMC.supportsLEDControl() -> Bool`
- `MagSafeSMC.setLEDMode(_:) -> Bool`, where the public mode type exposes only System and Off.
- Helper accepts `--probe`, `--reset`, or a fixed configuration-file path.

- [ ] Add tests around command parsing and fixed-value validation before adding helper behavior.
- [ ] Confirm the focused tests fail because the parser does not exist.
- [ ] Implement the two-value parser, SMC client, and helper executable.
- [ ] Add the root installer/uninstaller script and launchd job with no KeepAlive or polling.
- [ ] Build both debug and release targets.

### Task 3: Battery secondary panel

**Files:**
- Create: `Sources/StatusTrioCore/UI/MagSafeLEDView.swift`
- Modify: `Sources/StatusTrioCore/UI/BatteryStatusView.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: all `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`
- Modify affected UI test initializers.

**Interfaces:**
- Battery row calls `onOpenDetails`; its gear button remains a direct Battery Settings shortcut.
- Detail panel has Back, the System/Off switch, helper installation/removal actions, and explicit unsupported/error messages.

- [ ] Add localization keys to every language and update localization coverage.
- [ ] Add a UI test proving the Battery row exposes the details action.
- [ ] Confirm the focused test fails before wiring the action.
- [ ] Implement the secondary panel and controller wiring.
- [ ] Re-run focused UI, controller, and localization tests.

### Task 4: Packaging and verification

**Files:**
- Modify: `scripts/build-app.sh`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

**Interfaces:**
- Packaged app contains the helper, installer, and launchd template in fixed resource paths.
- Nested helper is signed before the outer app and packaging verifies all required artifacts.

- [ ] Update packaging and documentation.
- [ ] Run `swift test`.
- [ ] Run `swift build -c release`.
- [ ] Run `bash scripts/build-app.sh release no-open`.
- [ ] Inspect `git diff --check`, packaged artifacts, signatures, and final working-tree diff.
