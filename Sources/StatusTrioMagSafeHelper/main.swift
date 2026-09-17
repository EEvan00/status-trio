import Darwin
import Foundation
import MagSafeSMC
import Security

private let serviceName = ProcessInfo.processInfo.environment[
    "STATUS_TRIO_MACH_SERVICE"
] ?? MagSafeLEDXPC.serviceName(bundleIdentifier: nil)

private func executableURL() -> URL? {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
        .standardizedFileURL
        .resolvingSymlinksInPath()
}

private func enclosingAppURL() -> URL? {
    executableURL()?
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func designatedRequirement(for appURL: URL) -> String? {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
          let staticCode else { return nil }
    let validationFlags = SecCSFlags(
        rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    )
    guard SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess else {
        return nil
    }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
          let requirement else { return nil }
    var requirementString: CFString?
    guard SecRequirementCopyString(requirement, [], &requirementString) == errSecSuccess else {
        return nil
    }
    return requirementString as String?
}

private let clientRequirement: String = {
    guard let appURL = enclosingAppURL(),
          let requirement = designatedRequirement(for: appURL) else {
        fputs("Unable to derive the containing app's code-signing requirement.\n", stderr)
        exit(EXIT_FAILURE)
    }
    return requirement
}()

private final class HelperIdleLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var activeConnections = 0
    private var activeRequests = 0
    private var generation: UInt64 = 0
    private var pendingExit: DispatchWorkItem?
    private var isExiting = false

    func connectionBegan() -> Bool {
        lock.lock()
        guard !isExiting else {
            lock.unlock()
            return false
        }
        generation &+= 1
        activeConnections += 1
        let pendingExit = self.pendingExit
        self.pendingExit = nil
        lock.unlock()
        pendingExit?.cancel()
        return true
    }

    func connectionEnded() {
        lock.lock()
        activeConnections = max(0, activeConnections - 1)
        lock.unlock()
        scheduleIfIdle()
    }

    func requestBegan() {
        lock.lock()
        generation &+= 1
        activeRequests += 1
        let pendingExit = self.pendingExit
        self.pendingExit = nil
        lock.unlock()
        pendingExit?.cancel()
    }

    func requestEnded() {
        lock.lock()
        activeRequests = max(0, activeRequests - 1)
        lock.unlock()
        scheduleIfIdle()
    }

    func scheduleIfIdle() {
        lock.lock()
        guard activeConnections == 0, activeRequests == 0, !isExiting else {
            lock.unlock()
            return
        }
        generation &+= 1
        let expectedGeneration = generation
        pendingExit?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.exitIfIdle(generation: expectedGeneration)
        }
        pendingExit = workItem
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }

    private func exitIfIdle(generation expectedGeneration: UInt64) {
        lock.lock()
        let shouldExit = activeConnections == 0
            && activeRequests == 0
            && generation == expectedGeneration
            && !isExiting
        if shouldExit { isExiting = true }
        lock.unlock()
        if shouldExit { exit(EXIT_SUCCESS) }
    }
}

private final class MagSafeHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lifecycle: HelperIdleLifecycle
    private let service: MagSafeLEDXPCService

    init(lifecycle: HelperIdleLifecycle) {
        self.lifecycle = lifecycle
        service = MagSafeLEDXPCService { command in
            MagSafeSMC.setLEDMode(command)
        } requestDidBegin: {
            lifecycle.requestBegan()
        } requestDidEnd: {
            lifecycle.requestEnded()
        }
        super.init()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard connection.effectiveUserIdentifier != 0,
              lifecycle.connectionBegan() else { return false }
        let lease = MagSafeHelperConnectionLease(lifecycle: lifecycle)
        connection.invalidationHandler = {
            lease.end()
        }
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: MagSafeLEDXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private final class MagSafeHelperConnectionLease: @unchecked Sendable {
    private let lock = NSLock()
    private var lifecycle: HelperIdleLifecycle?

    init(lifecycle: HelperIdleLifecycle) {
        self.lifecycle = lifecycle
    }

    func end() {
        lock.lock()
        let lifecycle = self.lifecycle
        self.lifecycle = nil
        lock.unlock()
        lifecycle?.connectionEnded()
    }
}

private let lifecycle = HelperIdleLifecycle()
private let delegate = MagSafeHelperListenerDelegate(lifecycle: lifecycle)
private let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
lifecycle.scheduleIfIdle()
RunLoop.current.run()
