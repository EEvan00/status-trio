import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let magSafeLED: MagSafeLEDController
    let localization: Localization
    let statusBarController: StatusBarController
    let settingsWindowController: SettingsWindowController

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        magSafeLED: MagSafeLEDController,
        localization: Localization,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController
    ) {
        self.store = store
        self.settings = settings
        self.magSafeLED = magSafeLED
        self.localization = localization
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        magSafeLED: MagSafeLEDController? = nil,
        refreshInterval: Duration = .seconds(5)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            volumeMonitor: volumeMonitor,
            magSafeLED: magSafeLED,
            refreshInterval: refreshInterval
        )
    }

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let magSafeLED = MagSafeLEDController(
            hardwareProbe: SMCMagSafeLEDHardwareProbe(),
            helperManager: SystemMagSafeLEDHelperManager(),
            commandWriter: FileMagSafeLEDCommandWriter()
        )
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            connectionMonitor: NetworkConnectionMonitor(),
            volumeMonitor: VolumeMonitor(outputController: CoreAudioOutputController()),
            magSafeLED: magSafeLED,
            refreshInterval: settings.refreshInterval
        )
        let localization = Localization()
        let settingsWindowController = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization
        )
        let controller = StatusBarController(
            store: store,
            settings: settings,
            magSafeLED: magSafeLED,
            localization: localization,
            openSettings: { settingsWindowController.show() },
            quitAction: { NSApplication.shared.terminate(nil) }
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            magSafeLED: magSafeLED,
            localization: localization,
            statusBarController: controller,
            settingsWindowController: settingsWindowController
        )
    }
}
