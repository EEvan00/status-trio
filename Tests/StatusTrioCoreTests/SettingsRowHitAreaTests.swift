import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsRowHitAreaTests: XCTestCase {
    func testBatterySummaryExposesAFullWidthDetailsAction() {
        let localization = makeLocalization()
        let view = BatteryStatusView(
            battery: .placeholder,
            onOpenDetails: {},
            onOpenBatterySettings: {}
        )
        .environmentObject(localization)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 48)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { $0 >= 250 },
            "Expected a wide Battery details action, got \(hitAreaWidths)"
        )
    }

    func testPopupSettingsButtonUsesFullRowHitArea() {
        let localization = makeLocalization()
        let settings = makeSettings()
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitor(),
            wifiMonitor: EmptyWiFiMonitor(),
            volumeMonitor: EmptyVolumeMonitor()
        )
        let view = StatusPopoverView(
            store: store,
            settings: settings,
            magSafeLED: .unavailable(),
            requestWiFiNameAccess: {},
            openBatterySettings: {},
            openWiFiSettings: {},
            openLocationSettings: {},
            openBluetoothSettings: {},
            openSettings: {},
            openSoundSettings: {},
            quit: {}
        )
        .environmentObject(localization)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 600)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 268) < 0.5 },
            "Expected the Settings row to react across the popup content width, got \(hitAreaWidths)"
        )
    }

    func testPreferenceCheckboxRowUsesFullRowHitArea() {
        let localization = makeLocalization()
        let view = PreferenceCheckboxRow(
            label: .settingsBatteryShowPercentage,
            isOn: .constant(false)
        )
        .environmentObject(localization)

        let hitAreaWidths = interactiveSubViewWidths(
            for: view,
            size: NSSize(width: 300, height: 40)
        )

        XCTAssertTrue(
            hitAreaWidths.contains { abs($0 - 300) < 0.5 },
            "Expected the checkbox row to react across its full width, got \(hitAreaWidths)"
        )
    }

    private func interactiveSubViewWidths<V: View>(
        for view: V,
        size: NSSize
    ) -> [CGFloat] {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        return hostingView.subviews
            .filter { !$0.isHidden && $0.frame.height > 0 }
            .map(\.frame.width)
    }

    private func makeLocalization() -> Localization {
        let suiteName = "StatusTrioCoreTests.SettingsHitArea.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        return localization
    }

    private func makeSettings() -> SettingsStore {
        let suiteName = "StatusTrioCoreTests.SettingsHitAreaStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }
}

@MainActor
private final class EmptyBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class EmptyWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class EmptyVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
