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

The main app owns a `MagSafeLEDController`, preferences, and the Battery detail UI. A narrowly scoped root helper exposes an on-demand launchd Mach service and accepts only the raw values for `system` and `off`. The app sends one request over a privileged `NSXPCConnection`; the helper writes only the `ACLC` SMC key, verifies the result, returns that result directly in the XPC reply, and exits after 30 idle seconds. There are no request/result files, `WatchPaths`, or background polling. Off confirmation retries readback within the same request for up to about one second, without repeating the write; a persistent mismatch or unreadable value remains a failure.

The packaged app embeds the helper and launchd plist in the bundle structure required by `SMAppService`. The user explicitly chooses Install Helper and completes macOS approval. Uninstall requires a confirmed restore to system control before unregistering the helper. Ad-hoc signing and the private, firmware-dependent SMC interface are reported honestly in the UI and documentation.

## Security and compatibility

- Never accept an arbitrary SMC key or arbitrary byte value.
- Reject malformed requests and values other than `system` and `off`.
- Derive the containing app's exact designated requirement at runtime and apply it to every incoming XPC connection before it is resumed; fail closed if it cannot be derived.
- Register the bundled launch daemon through `SMAppService`; never execute a mutable bundled script as root.
- Persist a mode only after receiving the helper's direct verified reply.
- Compile with Swift 6.1/Xcode 16.4-compatible language features.

## Verification

Use unit tests for persistence, command validation, state transitions, reapplication, and localization. Run `swift test`, `swift build -c release`, and the non-opening app packaging workflow. Real LED changes and the administrator prompt require a compatible Apple Silicon Mac with MagSafe 3.
