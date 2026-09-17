# MagSafe LED Control Design

## Goal

Add a Battery secondary panel that lets the user choose whether the MagSafe indicator follows macOS or stays dark.

## Behavior

- On means system control (`ACLC = 0`).
- Off means the indicator is dark (`ACLC = 1`).
- The choice persists locally.
- When Off is selected, Status Trio reapplies it after launch, wake, and power-source changes without polling.
- Unsupported hardware, a missing helper, installation failure, and write failure remain distinct visible states.

## Architecture

The main app owns a `MagSafeLEDController`, preferences, and the Battery detail UI. A narrowly scoped root helper accepts only versioned `system` and `off` requests, writes only the `ACLC` SMC key, verifies the result, publishes a matching acknowledgement, and exits. A launchd `WatchPaths` job starts the helper only when the app atomically updates the request file; it is not a resident polling daemon.

The packaged app embeds the helper and launchd plist in the bundle structure required by `SMAppService`. The user explicitly chooses Install Helper and completes macOS approval. Uninstall requires a confirmed restore to system control before unregistering the helper. Ad-hoc signing and the private, firmware-dependent SMC interface are reported honestly in the UI and documentation.

## Security and compatibility

- Never accept an arbitrary SMC key or arbitrary byte value.
- Reject malformed requests and values other than `system` and `off`.
- Register the bundled launch daemon through `SMAppService`; never execute a mutable bundled script as root.
- Keep the writable configuration directory scoped to the installing user.
- Persist a mode only after receiving the helper's matching verified acknowledgement.
- Compile with Swift 6.1/Xcode 16.4-compatible language features.

## Verification

Use unit tests for persistence, command validation, state transitions, reapplication, and localization. Run `swift test`, `swift build -c release`, and the non-opening app packaging workflow. Real LED changes and the administrator prompt require a compatible Apple Silicon Mac with MagSafe 3.
