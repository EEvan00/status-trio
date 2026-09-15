import Foundation
import Testing
@testable import StatusTrioCore

struct PersonalHotspotTests {
    @Test func usesPercentageAndKeepsIdentitySeparateFromName() {
        let device = PersonalHotspot(row: ["id": "device-1", "name": "iPhone", "batteryLife": 87, "signalStrength": 2, "cellular": "4G"])
        #expect(device?.id == "device-1")
        #expect(device?.battery == 87)
        #expect(device?.signal == 2)
        #expect(device?.cellular == "4G")
    }

    @Test func invalidTelemetryIsNotPresentedAsRealMeasurements() {
        let device = PersonalHotspot(row: ["id": "device-1", "name": "iPhone", "batteryLife": 255, "signalStrength": -1, "cellular": ""])
        #expect(device?.battery == nil)
        #expect(device?.signal == nil)
        #expect(device?.cellular == nil)
        #expect(PersonalHotspot(row: ["name": "iPhone"]) == nil)
    }
}
