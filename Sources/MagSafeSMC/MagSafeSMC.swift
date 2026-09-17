import Foundation
import IOKit
import SMCDefinitions

public enum MagSafeLEDCommand: UInt8, Equatable, Sendable {
    case system = 0
    case off = 1

    public var smcValue: UInt8 { rawValue }
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
            readValue: { connection.readBytes(key: "ACLC")?.first }
        )
    }

    static func didApplyLEDMode(
        _ command: MagSafeLEDCommand,
        writeSucceeded: Bool,
        readValue: () -> UInt8?
    ) -> Bool {
        guard writeSucceeded else { return false }
        if command == .system {
            // ACLC 0 hands LED control back to macOS. The system may immediately
            // replace the readback with its current green or amber state.
            return true
        }
        // Firmware readback can lag behind a successful write. Confirm within
        // this request rather than reporting failure and requiring another click.
        // This runs in the helper, never on the app's main actor. Write only once.
        var lastValue: UInt8?
        for attempt in 0...20 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.05) }
            lastValue = readValue()
            if lastValue == command.smcValue { return true }
        }
        NSLog("MagSafe ACLC off confirmation timed out; last readback: %@",
              lastValue.map { String($0) } ?? "unavailable")
        return false
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
