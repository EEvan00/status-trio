import CoreWLAN
import Foundation
import Security

protocol WiFiCredentialStoring: AnyObject {
    /// Resolves a credential only for a user-selected network. Callers must
    /// never invoke this while scanning nearby networks.
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult
    /// Returns false on a Keychain write failure so the UI can report that the
    /// connection succeeded but the requested remembered-password save did not.
    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool
    func invalidate(for identity: WiFiNetworkIdentity)
}

extension WiFiCredentialStoring {
    func invalidate(for identity: WiFiNetworkIdentity) {}
}

/// Reads two deliberately separate credential namespaces on demand:
///
/// - the app-owned generic-password item for passwords the user chose to
///   remember in Status Trio; and
/// - CoreWLAN Wi-Fi password lookup in the user (including iCloud) and
///   system keychain domains, subject to system authorization.
///
/// CoreWLAN does not provide a public API to enumerate saved passwords, and
/// `associate(password: nil)` is not treated as credential reuse. The system
/// Keychain lookup is therefore attempted only after a click and its
/// cancellation, denial, locked-keychain, and read errors remain distinct.
final class KeychainWiFiPasswordStore: WiFiCredentialStoring, @unchecked Sendable {
    private let appService: String

    init(appService: String = "io.github.404404.StatusTrio.wifi-password") {
        self.appService = appService
    }

    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        let appResult = read(
            query: appReadQuery(for: identity),
            source: .appKeychain
        )
        switch appResult {
        case .credential, .issue:
            return appResult
        case .noCredential:
            return Self.findSystemCredential(ssid: identity.ssid)
        }
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        guard !password.isEmpty else { return false }
        let update = [kSecValueData as String: Data(password.utf8)]
        let updateStatus = SecItemUpdate(
            appUpdateQuery(for: identity) as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        let addStatus = SecItemAdd(appAddAttributes(password, for: identity) as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        if addStatus == errSecDuplicateItem {
            return SecItemUpdate(
                appUpdateQuery(for: identity) as CFDictionary,
                update as CFDictionary
            ) == errSecSuccess
        }
        return false
    }

    private func read(
        query: [String: Any],
        source: WiFiCredentialSource
    ) -> WiFiCredentialResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8),
                  !password.isEmpty else {
                return .issue(.readFailed)
            }
            return .credential(password, source)
        case errSecItemNotFound:
            return .noCredential
        case errSecUserCanceled:
            return .issue(.cancelled)
        case errSecAuthFailed:
            return .issue(.accessDenied)
        case errSecInteractionNotAllowed, errSecNotAvailable:
            return .issue(.keychainLocked)
        default:
            return .issue(.readFailed)
        }
    }

    private func appIdentity(for identity: WiFiNetworkIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            // Preserve raw SSID whitespace and keep security classes distinct.
            kSecAttrAccount as String: "\(identity.security.rawValue):\(identity.ssid)"
        ]
    }

    private func appReadQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        var query = appIdentity(for: identity)
        // Copy-matching controls are valid only for the read operation.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }

    private func appUpdateQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        // SecItemUpdate receives only an item identity, never return controls.
        appIdentity(for: identity)
    }

    private func appAddAttributes(_ password: String, for identity: WiFiNetworkIdentity) -> [String: Any] {
        var attributes = appIdentity(for: identity)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return attributes
    }

    static func findSystemCredential(
        ssid: String,
        lookup: (CWKeychainDomain, Data) -> (OSStatus, String?) = { domain, data in
            var password: NSString?
            let status = CWKeychainFindWiFiPassword(domain, data, &password)
            return (status, password as String?)
        }
    ) -> WiFiCredentialResult {
        for domain in [CWKeychainDomain.user, .system] {
            let (status, password) = lookup(domain, Data(ssid.utf8))
            switch status {
            case errSecSuccess:
                guard let password, !password.isEmpty else { return .issue(.readFailed) }
                return .credential(password, .systemKeychain)
            case errSecItemNotFound: continue
            // On current macOS the user-domain CoreWLAN service may return
            // 4097 even for a nonexistent SSID. The system domain remains usable.
            // Do not apply this fallback to authorization failures or cancellation.
            case 4097 where domain == .user: continue
            case errSecUserCanceled: return .issue(.cancelled)
            case errSecAuthFailed: return .issue(.accessDenied)
            case errSecInteractionNotAllowed, errSecNotAvailable: return .issue(.keychainLocked)
            default: return .issue(.readFailed)
            }
        }
        return .noCredential
    }
}
