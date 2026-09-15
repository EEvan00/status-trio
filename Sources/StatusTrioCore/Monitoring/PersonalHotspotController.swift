import Foundation
import HotspotBridge

struct PersonalHotspot: Identifiable, Equatable {
    let id: String
    let name: String
    let battery: Int?
    let signal: Int?
    let cellular: String?

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String, !id.isEmpty,
              let name = row["name"] as? String else { return nil }
        self.id = id
        self.name = name
        battery = (row["batteryLife"] as? NSNumber).flatMap {
            (0...100).contains($0.doubleValue) ? Int($0.doubleValue.rounded()) : nil
        }
        signal = (row["signalStrength"] as? NSNumber).flatMap {
            (0...4).contains($0.intValue) ? $0.intValue : nil
        }
        cellular = (row["cellular"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

@MainActor
final class PersonalHotspotController: ObservableObject {
    @Published private(set) var devices: [PersonalHotspot] = []
    @Published private(set) var connectingID: String?
    @Published private(set) var failed = false
    private let browser = STHotspotBrowser()
    private var active = false
    var didConnect: (() -> Void)?

    init() {
        browser.devicesChanged = { [weak self] rows in
            // The bridge delivers callbacks on the main queue.
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                self.devices = rows.compactMap { PersonalHotspot(row: $0) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
    }

    func start() {
        guard !active else { return }
        active = browser.start()
    }

    func stop() {
        active = false
        browser.stop()
        devices = []
        connectingID = nil
        failed = false
    }

    func connect(_ device: PersonalHotspot) {
        guard active, connectingID == nil else { return }
        failed = false
        connectingID = device.id
        browser.connectIdentifier(device.id) { [weak self] success in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                self.connectingID = nil
                self.failed = !success
                if success { self.didConnect?() }
            }
        }
    }
}
