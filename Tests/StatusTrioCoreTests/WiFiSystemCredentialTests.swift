import CoreWLAN
import Security
import Testing
@testable import StatusTrioCore

struct WiFiSystemCredentialTests {
    @Test func fallsBackToSystemDomainOnlyWhenUserItemIsMissing() {
        var domains: [CWKeychainDomain] = []
        let result = KeychainWiFiPasswordStore.findSystemCredential(ssid: " My WiFi ") { domain, data in
            domains.append(domain)
            #expect(String(data: data, encoding: .utf8) == " My WiFi ")
            return domain == .user ? (errSecItemNotFound, nil) : (errSecSuccess, "example-password")
        }
        #expect(domains == [.user, .system])
        #expect(result == .credential("example-password", .systemKeychain))
    }
    @Test func userServiceFailureStillChecksSystemPassword() {
        let result = KeychainWiFiPasswordStore.findSystemCredential(ssid: "WiFi") { domain, _ in
            domain == .user ? (4097, nil) : (errSecSuccess, "saved-password")
        }
        #expect(result == .credential("saved-password", .systemKeychain))
    }
    @Test func userServiceFailureWithMissingSystemItemAllowsPasswordEntry() {
        let result = KeychainWiFiPasswordStore.findSystemCredential(ssid: "New WiFi") { domain, _ in
            domain == .user ? (4097, nil) : (errSecItemNotFound, nil)
        }
        #expect(result == .noCredential)
    }
    @Test func cancellationIsNotTreatedAsMissingPassword() {
        var calls = 0
        let result = KeychainWiFiPasswordStore.findSystemCredential(ssid: "WiFi") { _, _ in
            calls += 1
            return (errSecUserCanceled, nil)
        }
        #expect(result == .issue(.cancelled))
        #expect(calls == 1)
    }
}
