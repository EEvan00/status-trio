import Foundation
import IOKit
import SMCDefinitions

public enum MagSafeLEDCommand: UInt8, Equatable, Sendable {
    case system = 0
    case off = 1

    public init?(configuration: String) {
        switch configuration {
        case "system\n": self = .system
        case "off\n": self = .off
        default: return nil
        }
    }

    public var smcValue: UInt8 { rawValue }
    public var configuration: String { self == .system ? "system\n" : "off\n" }
}

public struct MagSafeLEDRequest: Equatable, Sendable {
    public let id: UUID
    public let command: MagSafeLEDCommand

    public init(id: UUID = UUID(), command: MagSafeLEDCommand) {
        self.id = id
        self.command = command
    }

    public init?(configuration: String) {
        let parts = configuration.dropLast().split(separator: " ", omittingEmptySubsequences: false)
        guard configuration.hasSuffix("\n"), parts.count == 2,
              let id = UUID(uuidString: String(parts[0])),
              let command = MagSafeLEDCommand(configuration: String(parts[1]) + "\n") else {
            return nil
        }
        self.init(id: id, command: command)
    }

    public var configuration: String {
        "\(id.uuidString) \(command.configuration)"
    }
}

public struct MagSafeLEDResult: Equatable, Sendable {
    public let id: UUID
    public let succeeded: Bool

    public init(id: UUID, succeeded: Bool) {
        self.id = id
        self.succeeded = succeeded
    }

    public init?(configuration: String) {
        let parts = configuration.dropLast().split(separator: " ", omittingEmptySubsequences: false)
        guard configuration.hasSuffix("\n"), parts.count == 2,
              let id = UUID(uuidString: String(parts[0])) else { return nil }
        switch parts[1] {
        case "ok": self.init(id: id, succeeded: true)
        case "error": self.init(id: id, succeeded: false)
        default: return nil
        }
    }

    public var configuration: String {
        "\(id.uuidString) \(succeeded ? "ok" : "error")\n"
    }
}

public enum MagSafeLEDRequestFile {
    public static func consume(at url: URL) throws -> MagSafeLEDRequest {
        let claimedURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).processing-\(UUID().uuidString)"
        )
        try FileManager.default.moveItem(at: url, to: claimedURL)
        defer { try? FileManager.default.removeItem(at: claimedURL) }

        let data = try Data(contentsOf: claimedURL)
        guard let configuration = String(data: data, encoding: .utf8),
              let request = MagSafeLEDRequest(configuration: configuration) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return request
    }
}

public enum MagSafeSMC {
    public static func supportsLEDControl() -> Bool {
        guard let connection = SMCConnection() else { return false }
        return connection.keyInfo("ACLC")?.dataSize == 1
    }

    public static func setLEDMode(_ command: MagSafeLEDCommand) -> Bool {
        guard let connection = SMCConnection(),
              connection.keyInfo("ACLC")?.dataSize == 1,
              connection.writeByte(command.smcValue, key: "ACLC") else {
            return false
        }
        return didApplyLEDMode(
            command,
            writeSucceeded: true,
            readValue: connection.readBytes(key: "ACLC")?.first
        )
    }

    static func didApplyLEDMode(
        _ command: MagSafeLEDCommand,
        writeSucceeded: Bool,
        readValue: UInt8?
    ) -> Bool {
        guard writeSucceeded else { return false }
        if command == .system {
            // ACLC 0 hands LED control back to macOS. The system may immediately
            // replace the readback with its current green or amber state.
            return true
        }
        return readValue == command.smcValue
    }
}

private final class SMCConnection {
    private static let clientOpen: UInt32 = 0
    private static let clientClose: UInt32 = 1
    private static let handleEvent: UInt32 = 2
    private static let readKey: UInt8 = 5
    private static let writeKey: UInt8 = 6
    private static let getKeyInfo: UInt8 = 9
    private static let success: UInt8 = 0

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 1, &connection) == kIOReturnSuccess else {
            return nil
        }
        _ = IOConnectCallMethod(
            connection,
            Self.clientOpen,
            nil,
            0,
            nil,
            0,
            nil,
            nil,
            nil,
            nil
        )
    }

    deinit {
        guard connection != 0 else { return }
        _ = IOConnectCallMethod(
            connection,
            Self.clientClose,
            nil,
            0,
            nil,
            0,
            nil,
            nil,
            nil,
            nil
        )
        IOServiceClose(connection)
    }

    func keyInfo(_ key: String) -> StatusTrioSMCKeyInfoData? {
        var input = StatusTrioSMCParamStruct()
        input.key = fourCharacterCode(key)
        input.data8 = Self.getKeyInfo
        guard let output = call(input), output.result == Self.success else { return nil }
        return output.keyInfo
    }

    func writeByte(_ value: UInt8, key: String) -> Bool {
        var input = StatusTrioSMCParamStruct()
        input.key = fourCharacterCode(key)
        input.keyInfo.dataSize = 1
        input.data8 = Self.writeKey
        withUnsafeMutableBytes(of: &input.bytes) { bytes in
            bytes[0] = value
        }
        guard let output = call(input) else { return false }
        return output.result == Self.success
    }

    func readBytes(key: String) -> [UInt8]? {
        guard let info = keyInfo(key), info.dataSize <= 32 else { return nil }
        var input = StatusTrioSMCParamStruct()
        input.key = fourCharacterCode(key)
        input.keyInfo = info
        input.data8 = Self.readKey
        guard var output = call(input), output.result == Self.success else { return nil }
        return withUnsafeBytes(of: &output.bytes) { bytes in
            Array(bytes.prefix(Int(info.dataSize)))
        }
    }

    private func call(_ value: StatusTrioSMCParamStruct) -> StatusTrioSMCParamStruct? {
        var input = value
        var output = StatusTrioSMCParamStruct()
        var outputSize = MemoryLayout<StatusTrioSMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            Self.handleEvent,
            &input,
            MemoryLayout<StatusTrioSMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess ? output : nil
    }

    private func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
