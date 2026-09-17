import Foundation

public enum MagSafeLEDXPC {
    public static let defaultBundleIdentifier = "io.github.404404.StatusTrio"

    public static func serviceName(bundleIdentifier: String?) -> String {
        "\(bundleIdentifier ?? defaultBundleIdentifier).MagSafeHelper"
    }
}

@objc public protocol MagSafeLEDXPCProtocol {
    func setLEDMode(_ rawValue: UInt8, withReply reply: @escaping (Bool) -> Void)
}

public final class MagSafeLEDXPCService: NSObject, MagSafeLEDXPCProtocol {
    private let apply: @Sendable (MagSafeLEDCommand) -> Bool
    private let requestDidBegin: @Sendable () -> Void
    private let requestDidEnd: @Sendable () -> Void

    public init(
        apply: @escaping @Sendable (MagSafeLEDCommand) -> Bool,
        requestDidBegin: @escaping @Sendable () -> Void = {},
        requestDidEnd: @escaping @Sendable () -> Void = {}
    ) {
        self.apply = apply
        self.requestDidBegin = requestDidBegin
        self.requestDidEnd = requestDidEnd
    }

    public func setLEDMode(_ rawValue: UInt8, withReply reply: @escaping (Bool) -> Void) {
        requestDidBegin()
        defer { requestDidEnd() }
        guard let command = MagSafeLEDCommand(rawValue: rawValue) else {
            reply(false)
            return
        }
        reply(apply(command))
    }
}
