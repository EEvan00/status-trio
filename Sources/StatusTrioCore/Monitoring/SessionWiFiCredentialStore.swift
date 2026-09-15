import Foundation

/// Used by the serial credential worker. Secrets are retained only for this process.
final class SessionWiFiCredentialStore: WiFiCredentialStoring {
    private let underlying: any WiFiCredentialStoring
    private var credentials: [WiFiNetworkIdentity: WiFiCredentialResult] = [:]

    init(underlying: any WiFiCredentialStoring = KeychainWiFiPasswordStore()) {
        self.underlying = underlying
    }

    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        if let cached = credentials[identity] { return cached }
        let result = underlying.resolveCredential(for: identity)
        if case .credential = result { credentials[identity] = result }
        return result
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        credentials.removeValue(forKey: identity)
        return underlying.save(password, for: identity)
    }

    func invalidate(for identity: WiFiNetworkIdentity) {
        credentials.removeValue(forKey: identity)
        underlying.invalidate(for: identity)
    }
}
