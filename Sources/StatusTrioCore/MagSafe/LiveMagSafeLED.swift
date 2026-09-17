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

struct FileMagSafeLEDCommandWriter: MagSafeLEDCommandWriting {
    static let supportPath = "/Users/Shared/Status Trio"
    static let requestPath = "\(supportPath)/magsafe-led-request"
    static let resultPath = "\(supportPath)/magsafe-led-result"

    let requestURL: URL
    let resultURL: URL
    let timeout: Duration
    let retryInterval: Duration

    init(
        requestURL: URL = URL(fileURLWithPath: requestPath),
        resultURL: URL = URL(fileURLWithPath: resultPath),
        timeout: Duration = .seconds(3),
        retryInterval: Duration = .milliseconds(50)
    ) {
        self.requestURL = requestURL
        self.resultURL = resultURL
        self.timeout = timeout
        self.retryInterval = retryInterval
    }

    func write(_ mode: MagSafeLEDMode) async throws {
        let command: MagSafeLEDCommand = mode == .system ? .system : .off
        let request = MagSafeLEDRequest(command: command)
        try FileManager.default.createDirectory(
            at: requestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(request.configuration.utf8).write(to: requestURL, options: .atomic)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let data = try? Data(contentsOf: resultURL),
               let configuration = String(data: data, encoding: .utf8),
               let result = MagSafeLEDResult(configuration: configuration),
               result.id == request.id {
                guard result.succeeded else { throw MagSafeLEDCommandError.rejected }
                return
            }
            try await Task.sleep(for: retryInterval)
        }
        throw MagSafeLEDCommandError.timedOut
    }
}

private enum MagSafeLEDCommandError: Error {
    case rejected
    case timedOut
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
