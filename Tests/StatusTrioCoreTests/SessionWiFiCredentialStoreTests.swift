import Testing
@testable import StatusTrioCore

struct SessionWiFiCredentialStoreTests {
    @Test func authorizedCredentialIsReusedUntilInvalidated() {
        let source = CredentialSource()
        let cache = SessionWiFiCredentialStore(underlying: source)
        let identity = WiFiNetworkIdentity(ssid: "Home", security: .wpa2Personal)
        let expected = WiFiCredentialResult.credential("test-only-password", .systemKeychain)
        #expect(cache.resolveCredential(for: identity) == expected)
        source.result = .issue(.accessDenied)
        #expect(cache.resolveCredential(for: identity) == expected)
        cache.invalidate(for: identity)
        #expect(cache.resolveCredential(for: identity) == .issue(.accessDenied))
        source.result = expected
        #expect(cache.resolveCredential(for: identity) == expected)
    }

    @Test func cacheDoesNotSurviveNewStoreOrMixSecurityTypes() {
        let source = CredentialSource()
        let cache = SessionWiFiCredentialStore(underlying: source)
        let identity = WiFiNetworkIdentity(ssid: "Home", security: .wpa2Personal)
        _ = cache.resolveCredential(for: identity)
        source.result = .noCredential
        #expect(SessionWiFiCredentialStore(underlying: source).resolveCredential(for: identity) == .noCredential)
        #expect(cache.resolveCredential(for: WiFiNetworkIdentity(ssid: "Home", security: .wpa3Personal)) == .noCredential)
    }
}

private final class CredentialSource: WiFiCredentialStoring {
    var result: WiFiCredentialResult = .credential("test-only-password", .systemKeychain)
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult { result }
    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool { true }
}
