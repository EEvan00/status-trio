import AppKit
@preconcurrency import CoreBluetooth
import Foundation
import IOBluetooth

enum BluetoothWorkerResult: Sendable {
    case success([BluetoothDevice])
    case poweredOff
    case unavailable
    case failed
}

protocol BluetoothPairedDeviceReading: AnyObject {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void)
}

@MainActor
protocol BluetoothStateMonitoring: AnyObject {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)? { get set }
    func start()
    func stop()
}


/// Reads only the operating system paired-device database. It deliberately
/// does not perform a Bluetooth inquiry, so nearby BLE advertisements never
/// appear as paired devices.
final class IOBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    private let queue = DispatchQueue(label: "StatusTrio.IOBluetoothPairedDeviceWorker")

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        queue.async {
            guard let controller = IOBluetoothHostController.default() else {
                completion(.unavailable)
                return
            }
            // IOBluetoothHostController reports the HCI adapter state. The
            // previous inverted comparison reported powered off when it was on.
            guard controller.powerState == kBluetoothHCIPowerStateON else {
                completion(.poweredOff)
                return
            }
            // A nil result is not documented as an empty paired list, so it is
            // surfaced as a read failure rather than silently showing no devices.
            guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
                completion(.failed)
                return
            }

            let devices = pairedDevices.compactMap { device -> BluetoothDevice? in
                guard let identifier = device.addressString, !identifier.isEmpty else { return nil }
                let name = device.nameOrAddress ?? identifier
                return BluetoothDevice(
                    id: identifier,
                    name: name,
                    kind: self.kind(for: Int(device.deviceClassMajor)),
                    isConnected: device.isConnected()
                )
            }
            completion(.success(devices))
        }
    }

    private func kind(for majorClass: Int) -> BluetoothDeviceKind {
        // Bluetooth Class-of-Device major values are defined by the Bluetooth
        // specification. Unknown values remain generic rather than guessed.
        switch majorClass {
        case 0x01: .computer
        case 0x02: .phone
        case 0x04: .audio
        case 0x05: .peripheral
        default: .unknown
        }
    }
}

/// CoreBluetooth supplies the app authorization and the asynchronous adapter
/// lifecycle. IOBluetooth is intentionally not treated as an authorization
/// authority; it is used only for the paired-device database above.
@MainActor
final class CoreBluetoothStateMonitor: NSObject, @preconcurrency CBCentralManagerDelegate, BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private var centralManager: CBCentralManager?

    func start() {
        guard centralManager == nil else {
            publishState()
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        publishState()
    }

    func stop() {
        centralManager?.delegate = nil
        centralManager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState()
    }

    private func publishState() {
        onStateChange?(authorizationStatus(), managerState())
    }

    private func authorizationStatus() -> BluetoothAuthorizationStatus {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private func managerState() -> BluetoothManagerState {
        switch centralManager?.state ?? .unknown {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}

@MainActor
final class BluetoothDeviceController: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var availability: BluetoothAvailability = .idle

    private let worker: any BluetoothPairedDeviceReading
    private let stateMonitor: any BluetoothStateMonitoring
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var isActive = false
    private var requestGate = AsyncRequestGate()
    private var periodicRefreshTask: Task<Void, Never>?
    private var applicationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(
        worker: any BluetoothPairedDeviceReading = IOBluetoothPairedDeviceWorker(),
        stateMonitor: any BluetoothStateMonitoring = CoreBluetoothStateMonitor(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.worker = worker
        self.stateMonitor = stateMonitor
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        stateMonitor.onStateChange = { [weak self] authorization, managerState in
            self?.receiveSystemState(authorization: authorization, managerState: managerState)
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
    }


    var connectedDevices: [BluetoothDevice] {
        BluetoothDevicePresentation.grouped(devices).connected
    }

    /// Summary reads must not trigger the first Bluetooth permission prompt.
    func activateIfAuthorized() {
        guard CBManager.authorization == .allowedAlways else { return }
        activate()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        registerSystemObservers()
        stateMonitor.start()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        _ = requestGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        removeSystemObservers()
        stateMonitor.stop()
        // Closing the detail view does not invalidate the last known state.
    }

    func refresh() {
        guard isActive, availability == .available else { return }
        let request = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.requestGate.accepts(request) else { return }
                switch result {
                case let .success(devices):
                    self.devices = devices
                    self.availability = .available
                case .poweredOff:
                    self.availability = .poweredOff
                    self.stopPeriodicRefresh()
                case .unavailable:
                    self.availability = .unavailable
                    self.stopPeriodicRefresh()
                case .failed:
                    self.availability = .failed
                }
            }
        }
    }

    private func receiveSystemState(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) {
        guard isActive else { return }
        let mappedAvailability = BluetoothAvailabilityMapper.preliminary(
            authorization: authorization,
            managerState: managerState
        )
        availability = mappedAvailability

        if mappedAvailability == .available {
            schedulePeriodicRefresh()
            refresh()
        } else {
            _ = requestGate.advance()
            stopPeriodicRefresh()
        }
    }

    private func registerSystemObservers() {
        guard applicationObserver == nil, wakeObserver == nil else { return }
        applicationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
        wakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
    }

    private func removeSystemObservers() {
        if let applicationObserver {
            notificationCenter.removeObserver(applicationObserver)
        }
        if let wakeObserver {
            workspaceNotificationCenter.removeObserver(wakeObserver)
        }
        applicationObserver = nil
        wakeObserver = nil
    }

    private func refreshAfterSystemEvent() {
        guard isActive else { return }
        stateMonitor.start()
    }

    private func schedulePeriodicRefresh() {
        guard periodicRefreshTask == nil else { return }
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.isActive, self.availability == .available else { return }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }
}
