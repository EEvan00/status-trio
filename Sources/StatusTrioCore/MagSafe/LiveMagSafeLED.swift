import Darwin
import Foundation
import IOKit.ps
import MagSafeSMC
import ServiceManagement

struct SMCMagSafeLEDHardwareProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any] else {
                return false
            }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}

protocol MagSafeLEDXPCTransporting: Sendable {
    func setLEDMode(rawValue: UInt8) async throws -> Bool
}

struct XPCMagSafeLEDCommandWriter: MagSafeLEDCommandWriting {
    private let transport: any MagSafeLEDXPCTransporting

    init(transport: any MagSafeLEDXPCTransporting = SystemMagSafeLEDXPCTransport()) {
        self.transport = transport
    }

    func write(_ mode: MagSafeLEDMode) async throws {
        let command: MagSafeLEDCommand = mode == .system ? .system : .off
        guard try await transport.setLEDMode(rawValue: command.rawValue) else {
            throw MagSafeLEDCommandError.rejected
        }
    }
}

private final class SystemMagSafeLEDXPCTransport: MagSafeLEDXPCTransporting, @unchecked Sendable {
    private let serviceName: String

    init(
        serviceName: String = MagSafeLEDXPC.serviceName(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    ) {
        self.serviceName = serviceName
    }

    func setLEDMode(rawValue: UInt8) async throws -> Bool {
        let coordinator = MagSafeLEDXPCRequestCoordinator()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connection = NSXPCConnection(
                    machServiceName: serviceName,
                    options: .privileged
                )
                let request = MagSafeLEDXPCRequest(
                    connection: connection,
                    continuation: continuation
                )
                coordinator.install(request)
                connection.remoteObjectInterface = NSXPCInterface(with: MagSafeLEDXPCProtocol.self)
                connection.interruptionHandler = {
                    request.finish(.failure(MagSafeLEDCommandError.connectionInterrupted))
                }
                connection.invalidationHandler = {
                    request.finish(.failure(MagSafeLEDCommandError.connectionInvalidated))
                }
                coordinator.sendIfNotCancelled {
                    connection.resume()

                    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                        request.finish(.failure(error))
                    }) as? MagSafeLEDXPCProtocol else {
                        request.finish(.failure(MagSafeLEDCommandError.invalidProxy))
                        return
                    }
                    proxy.setLEDMode(rawValue) { succeeded in
                        request.finish(.success(succeeded))
                    }
                }
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}

final class MagSafeLEDXPCRequestCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var request: MagSafeLEDXPCRequest?
    private var isCancelled = false
    private var hasSent = false

    fileprivate func install(_ request: MagSafeLEDXPCRequest) {
        lock.lock()
        self.request = request
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel {
            request.finish(.failure(CancellationError()))
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let request = hasSent ? nil : request
        lock.unlock()
        request?.finish(.failure(CancellationError()))
    }

    func sendIfNotCancelled(_ send: () -> Void) {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        hasSent = true
        send()
        lock.unlock()
    }
}

private final class MagSafeLEDXPCRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var continuation: CheckedContinuation<Bool, Error>?

    init(
        connection: NSXPCConnection,
        continuation: CheckedContinuation<Bool, Error>
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        continuation.resume(with: result)
        connection?.invalidate()
    }
}

private enum MagSafeLEDCommandError: Error {
    case rejected
    case invalidProxy
    case connectionInterrupted
    case connectionInvalidated
}

struct SystemMagSafeLEDHelperManager: MagSafeLEDHelperManaging {
    static let plistName = "com.status-trio.magsafe-helper.plist"

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    var status: MagSafeLEDHelperStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func install() async throws {
        try service.register()
    }

    func uninstall() async throws {
        try await service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
