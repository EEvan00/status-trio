import AppKit
import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    static let popupDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var popupSnapshot: StatusSnapshot
    @Published private(set) var liveVolume: VolumeStatus
    let wifiNetworks: WiFiNetworkController
    let bluetoothDevices: BluetoothDeviceController

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let connectionMonitor: (any NetworkConnectionMonitoring)?
    private let volumeMonitor: any VolumeMonitoring
    private let volumeController: (any VolumeControlling)?
    private var refreshInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let popupDebounceSleep: @Sendable (Duration) async throws -> Void
    private let wakeNotificationCenter: NotificationCenter
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var popupPublishTask: Task<Void, Never>?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false
    private var isPopoverVisible = false

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        popupDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        wifiNetworks: WiFiNetworkController = WiFiNetworkController(),
        bluetoothDevices: BluetoothDeviceController = BluetoothDeviceController(),
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.connectionMonitor = connectionMonitor
        self.volumeMonitor = volumeMonitor
        self.volumeController = volumeMonitor as? any VolumeControlling
        self.refreshInterval = refreshInterval
        self.sleep = sleep
        self.popupDebounceSleep = popupDebounceSleep
        self.wakeNotificationCenter = wakeNotificationCenter
        self.wifiNetworks = wifiNetworks
        self.bluetoothDevices = bluetoothDevices
        self.snapshot = initialSnapshot
        self.popupSnapshot = initialSnapshot
        self.liveVolume = initialSnapshot.volume
    }

    deinit {
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
        }
        monitorTasks.forEach { $0.cancel() }
        refreshTask?.cancel()
        popupPublishTask?.cancel()
    }

    func start() {
        guard !hasStarted, !hasStopped else { return }
        hasStarted = true
        wifiMonitor.setDetailsVisible(false)
        volumeMonitor.setDetailsVisible(false)

        wakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recoverAll()
                self.refreshAll()
            }
        }

        batteryMonitor.start()
        wifiMonitor.start()
        connectionMonitor?.start()
        volumeMonitor.start()

        let batteryUpdates = batteryMonitor.updates
        let wifiUpdates = wifiMonitor.updates
        let connectionUpdates = connectionMonitor?.updates
        let volumeUpdates = volumeMonitor.updates
        var tasks = [
            Task { [weak self] in
                for await value in batteryUpdates {
                    guard let self else { return }
                    self.applyBattery(value)
                }
            },
            Task { [weak self] in
                for await value in wifiUpdates {
                    guard let self else { return }
                    self.applyWiFi(value)
                }
            },
            Task { [weak self] in
                for await value in volumeUpdates {
                    guard let self else { return }
                    self.applyVolume(value)
                }
            }
        ]
        if let connectionUpdates {
            tasks.append(Task { [weak self] in
                for await value in connectionUpdates {
                    guard let self else { return }
                    self.applyConnection(value)
                }
            })
        }
        monitorTasks = tasks

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let sleep = self?.sleep, let interval = self?.refreshInterval else { return }
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        batteryMonitor.stop()
        wifiMonitor.stop()
        connectionMonitor?.stop()
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        popupPublishTask?.cancel()
        popupPublishTask = nil
        wifiNetworks.deactivate()
        bluetoothDevices.deactivate()
    }

    var isVolumeControlAvailable: Bool {
        volumeController != nil && liveVolume.scalar != nil
    }

    func setVolume(_ scalar: Double) {
        guard !hasStopped,
              volumeController != nil,
              scalar.isFinite else {
            return
        }
        liveVolume = liveVolume.replacingScalar(min(1, max(0, scalar)))
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.setVolume(liveVolume.scalar ?? 0)
    }

    func toggleMute() {
        guard !hasStopped,
              volumeController != nil,
              liveVolume.scalar != nil else {
            return
        }
        liveVolume = liveVolume.replacingMuted(!liveVolume.isMuted)
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.toggleMute()
    }

    func selectOutputDevice(_ device: AudioOutputDevice) {
        guard !hasStopped else { return }
        volumeController?.selectOutputDevice(device.id)
    }

    func requestWiFiNameAccess() {
        guard !hasStopped else { return }
        wifiMonitor.requestNameAccess()
    }

    func refreshForPopoverOpening() {
        setPopoverVisible(true)
    }

    func setRefreshInterval(_ interval: Duration) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
    }

    func setPopoverVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        isPopoverVisible = visible
        wifiMonitor.setDetailsVisible(visible)
        volumeMonitor.setDetailsVisible(visible)

        guard visible else { return }
        popupPublishTask?.cancel()
        popupPublishTask = nil
        popupSnapshot = snapshot
        refreshAll()
        wifiNetworks.refresh(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func activateWiFiPanel() {
        guard !hasStopped else { return }
        wifiNetworks.activate(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func activateBluetoothPanel() {
        guard !hasStopped else { return }
        bluetoothDevices.activate()
    }

    func closePopoverDetails() {
        wifiNetworks.deactivate()
        bluetoothDevices.deactivate()
    }

    func refreshAll() {
        guard !hasStopped else { return }
        batteryMonitor.refresh()
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }

    private func recoverAll() {
        batteryMonitor.recover()
        wifiMonitor.recover()
        connectionMonitor?.recover()
        volumeMonitor.recover()
    }

    private func applyBattery(_ value: BatteryStatus) {
        publish(snapshot.replacingBattery(value))
    }

    private func applyWiFi(_ value: WiFiStatus) {
        let previous = snapshot.wifi
        publish(snapshot.replacingWiFi(value))
        if previous.nameAccess != value.nameAccess || previous.ssid != value.ssid || previous.state != value.state {
            wifiNetworks.refresh(nameAccess: value.nameAccess)
        }
    }

    private func applyConnection(_ value: NetworkConnection) {
        publish(snapshot.replacingConnection(value))
    }

    private func applyVolume(_ value: VolumeStatus) {
        liveVolume = value
        publish(snapshot.replacingVolume(value))
    }

    private func publish(_ next: StatusSnapshot) {
        guard !hasStopped, next != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = next
        snapshot = next
        schedulePopupSnapshot(next)
    }

    private func schedulePopupSnapshot(_ next: StatusSnapshot) {
        guard isPopoverVisible else { return }
        popupPublishTask?.cancel()
        popupPublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.popupDebounceSleep(Self.popupDebounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.popupSnapshot = next
        }
    }
}

private extension VolumeStatus {
    func replacingScalar(_ scalar: Double) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            outputDevices: outputDevices
        )
    }

    func replacingMuted(_ isMuted: Bool) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            outputDevices: outputDevices
        )
    }
}

private extension StatusSnapshot {
    func replacingBattery(_ value: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: value, wifi: wifi, connection: connection, volume: volume)
    }

    func replacingWiFi(_ value: WiFiStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: value, connection: connection, volume: volume)
    }

    func replacingConnection(_ value: NetworkConnection) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: value, volume: volume)
    }

    func replacingVolume(_ value: VolumeStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: value)
    }
}
