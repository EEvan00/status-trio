import AppKit
import Combine
import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class SystemStatusStoreTests: XCTestCase {
    func testStoreMergesIndependentMonitorUpdates() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        let updatesApplied = expectation(description: "independent monitor updates applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .connected,
                      snapshot.volume.scalar == 0.6 else { return }
                updatesApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        wifi.send(WiFiStatus(state: .connected, rssi: -60))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [updatesApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testPopupDebounceIntervalIs500Milliseconds() {
        XCTAssertEqual(SystemStatusStore.popupDebounceInterval, .milliseconds(500))
    }

    func testPopupSnapshotDebouncesRapidUpdates() async {
        let battery = FakeBatteryMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )
        let finalPopupUpdate = expectation(description: "final popup snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$popupSnapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery.percentage == 55 {
                    finalPopupUpdate.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        store.setPopoverVisible(true)
        battery.send(makeBattery(percentage: 42))
        await sleeper.waitForCallCount(1)
        battery.send(makeBattery(percentage: 55))
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)

        sleeper.releaseAll()
        await fulfillment(of: [finalPopupUpdate], timeout: 1)

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 55)
        cancellables.removeAll()
        store.stop()
    }

    func testPopoverVisibilityUpdatesDetailsAndRefreshes() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        XCTAssertEqual(wifi.detailsVisibility, [false])
        XCTAssertEqual(volume.detailsVisibility, [false])
        let initialWiFiRefreshCount = wifi.refreshCount
        let initialVolumeRefreshCount = volume.refreshCount

        store.setPopoverVisible(true)
        XCTAssertEqual(wifi.detailsVisibility, [false, true])
        XCTAssertEqual(volume.detailsVisibility, [false, true])
        XCTAssertEqual(wifi.refreshCount, initialWiFiRefreshCount + 1)
        XCTAssertEqual(volume.refreshCount, initialVolumeRefreshCount + 1)

        store.setPopoverVisible(false)
        XCTAssertEqual(wifi.detailsVisibility, [false, true, false])
        XCTAssertEqual(volume.detailsVisibility, [false, true, false])
        store.stop()
    }

    func testSetVolumeUpdatesVisibleVolumeImmediately() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        volume.send(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await drainMainActorTasks()

        store.setVolume(0.7)

        XCTAssertEqual(store.liveVolume.scalar, 0.7)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.7)
        XCTAssertEqual(volume.setVolumeValues, [0.7])

        sleeper.releaseAll()
        store.stop()
    }

    func testLiveVolumeUsesSnapshotWhilePopupSnapshotIsDebounced() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )
        let liveUpdate = expectation(description: "live volume snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.volume.scalar == 0.42 {
                    liveUpdate.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        store.setPopoverVisible(true)
        volume.send(
            VolumeStatus(
                scalar: 0.42,
                isMuted: false,
                deviceName: "Speaker"
            )
        )
        await fulfillment(of: [liveUpdate], timeout: 1)
        await sleeper.waitForCallCount(1)

        XCTAssertEqual(store.snapshot.volume.scalar, 0.42)
        XCTAssertNil(store.popupSnapshot.volume.scalar)
        XCTAssertEqual(store.liveVolume.scalar, 0.42)

        sleeper.releaseAll()
        cancellables.removeAll()
        store.stop()
    }

    func testOpeningPopupFlushesLatestSnapshotAndRefreshesMonitors() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        let batteryUpdated = expectation(description: "battery snapshot published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery.percentage == 42 {
                    batteryUpdated.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        await fulfillment(of: [batteryUpdated], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)

        store.refreshForPopoverOpening()

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 42)
        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        cancellables.removeAll()
        store.stop()
    }

    func testStopCancelsPendingPopupSnapshot() async {
        let battery = FakeBatteryMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        store.setPopoverVisible(true)
        battery.send(makeBattery(percentage: 42))
        await sleeper.waitForCallCount(1)
        store.stop()

        sleeper.releaseAll()
        await drainMainActorTasks()

        XCTAssertEqual(store.popupSnapshot.battery.percentage, 100)
    }

    func testEqualSnapshotsDoNotPublishTwice() async {
        let battery = FakeBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60)
        )

        let barrierPublished = expectation(description: "barrier snapshot published")
        var placeholderPublishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery == .placeholder {
                    placeholderPublishCount += 1
                }
                if snapshot.battery.percentage == 42 {
                    barrierPublished.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        battery.send(.placeholder)
        battery.send(.placeholder)
        battery.send(makeBattery(percentage: 42))
        await fulfillment(of: [barrierPublished], timeout: 1)

        XCTAssertEqual(placeholderPublishCount, 1)
        cancellables.removeAll()
        store.stop()
    }

    func testMakeStoreUsesInjectedConnectionMonitor() async {
        let connection = FakeNetworkConnectionMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            connectionMonitor: connection,
            volumeMonitor: FakeVolumeMonitor()
        )
        let updateApplied = expectation(description: "injected connection monitor update applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.connection == .ethernet else { return }
                updateApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        connection.send(.ethernet)
        await fulfillment(of: [updateApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.connection, .ethernet)
        cancellables.removeAll()
        store.stop()
    }

    func testMakeStoreUsesInjectedMonitors() async {
        let battery = FakeBatteryMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor()
        )

        let updateApplied = expectation(description: "injected monitor update applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 55 else { return }
                updateApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 55))
        await fulfillment(of: [updateApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        cancellables.removeAll()
        store.stop()
    }

    func testStartTwiceStartsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        store.stop()
    }

    func testRequestWiFiNameAccessForwardsToMonitor() {
        let wifi = FakeWiFiMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: wifi,
            volume: FakeVolumeMonitor()
        )

        store.start()
        store.requestWiFiNameAccess()

        XCTAssertEqual(wifi.nameAccessRequestCount, 1)
        store.stop()
    }

    func testStopTwiceStopsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.stop()

        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testBufferedMonitorUpdateAfterStopDoesNotMutateSnapshot() async {
        let battery = FakeBatteryMonitor()
        let store = makeStore(
            battery: battery,
            wifi: FakeWiFiMonitor(),
            volume: FakeVolumeMonitor()
        )

        store.start()
        let stoppedSnapshot = store.snapshot
        battery.send(makeBattery(percentage: 42))
        store.stop()
        await drainMainActorTasks()

        XCTAssertEqual(store.snapshot, stoppedSnapshot)
        XCTAssertEqual(battery.stopCount, 1)
    }

    func testStartAfterStopDoesNotStartMonitorsAgain() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testPeriodicRefreshUsesInjectedSleep() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
    }

    func testChangingRefreshIntervalAffectsNextSleepCycle() async {
        let sleeper = ManualSleeper()
        let battery = FakeBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        store.start()
        await sleeper.waitForCallCount(1)

        store.setRefreshInterval(.seconds(5))
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(sleeper.durations, [.seconds(60), .seconds(5)])
        store.stop()
    }

    func testStopPreventsFurtherPeriodicRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        store.refreshAll()

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
    }

    func testWakeNotificationRefreshesAllMonitorsExactlyOnce() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let wakeCenter = NotificationCenter()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            wakeNotificationCenter: wakeCenter
        )
        let refreshed = expectation(description: "all monitors refreshed after wake")
        refreshed.assertForOverFulfill = true
        var recoveryAndRefreshOrder: [String] = []
        battery.onRecover = { recoveryAndRefreshOrder.append("battery.recover") }
        wifi.onRecover = { recoveryAndRefreshOrder.append("wifi.recover") }
        volume.onRecover = { recoveryAndRefreshOrder.append("volume.recover") }
        battery.onRefresh = { recoveryAndRefreshOrder.append("battery.refresh") }
        wifi.onRefresh = { recoveryAndRefreshOrder.append("wifi.refresh") }
        volume.onRefresh = {
            recoveryAndRefreshOrder.append("volume.refresh")
            refreshed.fulfill()
        }

        store.start()
        wakeCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await fulfillment(of: [refreshed], timeout: 1)

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        XCTAssertEqual(battery.recoverCount, 1)
        XCTAssertEqual(wifi.recoverCount, 1)
        XCTAssertEqual(volume.recoverCount, 1)
        XCTAssertEqual(recoveryAndRefreshOrder, [
            "battery.recover",
            "wifi.recover",
            "volume.recover",
            "battery.refresh",
            "wifi.refresh",
            "volume.refresh"
        ])
        store.stop()
    }

    func testWakeNotificationReappliesOffMagSafeModeOnce() async {
        let wakeCenter = NotificationCenter()
        let writer = StoreRecordingMagSafeCommandWriter()
        let controller = makeReadyMagSafeController(writer: writer)
        let reapplied = expectation(description: "MagSafe off mode reapplied after wake")
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            magSafeLED: controller,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: wakeCenter
        )

        store.start()
        controller.setLightEnabled(false)
        await waitUntilIdle(controller)
        writer.modes.removeAll()
        writer.onWrite = { reapplied.fulfill() }
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fulfillment(of: [reapplied], timeout: 1)

        XCTAssertEqual(writer.modes, [.off])
        store.stop()
    }

    func testStartReappliesPersistedOffMagSafeModeOnce() async {
        let writer = StoreRecordingMagSafeCommandWriter()
        let controller = makeReadyMagSafeController(writer: writer)
        controller.setLightEnabled(false)
        await waitUntilIdle(controller)
        writer.modes.removeAll()
        let reapplied = expectation(description: "MagSafe off mode reapplied at launch")
        writer.onWrite = { reapplied.fulfill() }
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            magSafeLED: controller,
            refreshInterval: .seconds(60)
        )

        store.start()
        await fulfillment(of: [reapplied], timeout: 1)

        XCTAssertEqual(writer.modes, [.off])
        store.stop()
    }

    func testPowerSourceTransitionReappliesOffMagSafeModeWithoutPolling() async {
        let battery = FakeBatteryMonitor()
        let writer = StoreRecordingMagSafeCommandWriter()
        let controller = makeReadyMagSafeController(writer: writer)
        let reapplied = expectation(description: "MagSafe off mode reapplied after power transition")
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            magSafeLED: controller,
            refreshInterval: .seconds(60)
        )

        store.start()
        controller.setLightEnabled(false)
        await waitUntilIdle(controller)
        writer.modes.removeAll()
        writer.onWrite = { reapplied.fulfill() }
        battery.send(makeBattery(percentage: 80, connectedToPower: true))
        await fulfillment(of: [reapplied], timeout: 1)
        battery.send(makeBattery(percentage: 79, connectedToPower: true))
        await drainMainActorTasks()

        XCTAssertEqual(writer.modes, [.off])
        store.stop()
    }

    func testWakeNotificationAfterStopDoesNotRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let wakeCenter = SpyWakeNotificationCenter()
        let store = makeStore(
            battery: battery,
            wifi: wifi,
            volume: volume,
            wakeNotificationCenter: wakeCenter
        )
        let noRefresh = expectation(description: "no refresh after stop")
        noRefresh.isInverted = true
        noRefresh.assertForOverFulfill = true
        battery.onRefresh = { noRefresh.fulfill() }

        store.start()
        XCTAssertEqual(wakeCenter.addCount, 1)
        store.stop()
        XCTAssertEqual(wakeCenter.removeCount, 1)
        wakeCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await fulfillment(of: [noRefresh], timeout: 0.2)

        XCTAssertEqual(battery.refreshCount, 0)
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)
        XCTAssertEqual(battery.recoverCount, 0)
        XCTAssertEqual(wifi.recoverCount, 0)
        XCTAssertEqual(volume.recoverCount, 0)
    }

    func testStoreDeallocatesWhenMonitorTasksOnlyReferenceItWeakly() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        weak var weakStore: SystemStatusStore?

        do {
            var store: SystemStatusStore? = makeStore(
                battery: battery,
                wifi: wifi,
                volume: volume
            )
            weakStore = store
            store?.start()
            store = nil
        }

        XCTAssertNil(weakStore)
        battery.stop()
        wifi.stop()
        volume.stop()
    }

    func testUnavailableMonitorDoesNotPreventOtherValuesFromMerging() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)
        let merged = expectation(description: "available monitors merged around unavailable Wi-Fi")
        let fulfillOnce = SingleFulfillment()
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .unavailable,
                      snapshot.volume.scalar == 0.6 else { return }
                fulfillOnce.fulfill(merged)
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        wifi.send(.placeholder)
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [merged], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .unavailable)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testFinishedMonitorStreamDoesNotPreventOtherMonitorsFromPublishing() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)
        let merged = expectation(description: "remaining monitors continue publishing")
        let fulfillOnce = SingleFulfillment()
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .unavailable,
                      snapshot.volume.scalar == 0.6 else { return }
                fulfillOnce.fulfill(merged)
            }
            .store(in: &cancellables)

        store.start()
        wifi.finishUpdates()
        battery.send(makeBattery(percentage: 42))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [merged], timeout: 1)

        XCTAssertEqual(wifi.finishCount, 1)
        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .unavailable)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testConnectionMonitorUpdateIsPublished() async {
        let connection = FakeNetworkConnectionMonitor()
        let store = makeStore(
            battery: FakeBatteryMonitor(),
            wifi: FakeWiFiMonitor(),
            volume: FakeVolumeMonitor(),
            connection: connection
        )
        let updated = expectation(description: "connection update published")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.connection == .ethernet else { return }
                updated.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        connection.send(.ethernet)
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(store.snapshot.connection, .ethernet)
        cancellables.removeAll()
        store.stop()
    }

    private func makeStore(
        battery: FakeBatteryMonitor,
        wifi: FakeWiFiMonitor,
        volume: FakeVolumeMonitor,
        connection: FakeNetworkConnectionMonitor? = nil,
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) -> SystemStatusStore {
        if let connection {
            return SystemStatusStore(
                batteryMonitor: battery,
                wifiMonitor: wifi,
                connectionMonitor: connection,
                volumeMonitor: volume,
                refreshInterval: .seconds(60),
                wakeNotificationCenter: wakeNotificationCenter
            )
        }
        return SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: wakeNotificationCenter
        )
    }

    private func makeBattery(
        percentage: Int,
        connectedToPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: connectedToPower
        )
    }

    private func makeReadyMagSafeController(
        writer: StoreRecordingMagSafeCommandWriter
    ) -> MagSafeLEDController {
        let defaults = UserDefaults(
            suiteName: "SystemStatusStoreTests.MagSafeLED.\(UUID().uuidString)"
        )!
        return MagSafeLEDController(
            defaults: defaults,
            hardwareProbe: StoreSupportedMagSafeProbe(),
            helperManager: StoreInstalledMagSafeHelperManager(),
            commandWriter: writer
        )
    }

    private func waitUntilIdle(_ controller: MagSafeLEDController) async {
        while controller.isBusy { await Task.yield() }
    }

    private func drainMainActorTasks() async {
        await Task { @MainActor in }.value
    }
}

private struct StoreSupportedMagSafeProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool { true }
}

private struct StoreInstalledMagSafeHelperManager: MagSafeLEDHelperManaging {
    var status: MagSafeLEDHelperStatus { .enabled }
    func install() async throws {}
    func uninstall() async throws {}
    func openSystemSettings() {}
}

private final class StoreRecordingMagSafeCommandWriter: MagSafeLEDCommandWriting, @unchecked Sendable {
    var modes: [MagSafeLEDMode] = []
    var onWrite: (() -> Void)?

    func write(_ mode: MagSafeLEDMode) async throws {
        modes.append(mode)
        onWrite?()
    }
}

@MainActor
private final class ManualSleeper {
    private(set) var callCount = 0
    private(set) var completionCount = 0
    private(set) var durations: [Duration] = []

    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration = .zero) async {
        callCount += 1
        durations.append(duration)
        resumeCallWaiters()

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
        }

        completionCount += 1
        resumeCompletionWaiters()
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func waitForCompletionCount(_ count: Int) async {
        guard completionCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }

    func releaseNext() {
        guard !sleepContinuations.isEmpty else { return }
        sleepContinuations.removeFirst().resume()
    }

    func releaseAll() {
        let continuations = sleepContinuations
        sleepContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeCallWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in callWaiters {
            if callCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }

    private func resumeCompletionWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in completionWaiters {
            if completionCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        completionWaiters = remaining
    }
}

@MainActor
private final class SingleFulfillment {
    private var hasFulfilled = false

    func fulfill(_ expectation: XCTestExpectation) {
        guard !hasFulfilled else { return }
        hasFulfilled = true
        expectation.fulfill()
    }
}

private final class SpyWakeNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var addCount = 0
    private(set) var removeCount = 0

    override func addObserver(
        forName name: NSNotification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        addCount += 1
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        removeCount += 1
        super.removeObserver(observer)
    }
}

@MainActor
private final class FakeNetworkConnectionMonitor: NetworkConnectionMonitoring {
    let updates: AsyncStream<NetworkConnection>
    private let continuation: AsyncStream<NetworkConnection>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func recover() {}
    func send(_ value: NetworkConnection) { continuation.yield(value) }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func send(_ value: BatteryStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    private(set) var finishCount = 0
    private(set) var nameAccessRequestCount = 0
    private(set) var detailsVisibility: [Bool] = []
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func requestNameAccess() {
        nameAccessRequestCount += 1
    }

    func setDetailsVisible(_ visible: Bool) {
        detailsVisibility.append(visible)
    }
    func send(_ value: WiFiStatus) { continuation.yield(value) }
    func finishUpdates() {
        finishCount += 1
        continuation.finish()
    }
}

@MainActor
private final class FakeVolumeMonitor: VolumeMonitoring, VolumeControlling {
    let updates: AsyncStream<VolumeStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private(set) var recoverCount = 0
    private(set) var setVolumeValues: [Double] = []
    private(set) var toggleMuteCount = 0
    private(set) var selectedOutputDeviceIDs: [AudioDeviceID] = []
    private(set) var detailsVisibility: [Bool] = []
    var onRecover: (() -> Void)?
    var onRefresh: (() -> Void)?
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() {
        refreshCount += 1
        onRefresh?()
    }
    func recover() {
        recoverCount += 1
        onRecover?()
    }
    func setVolume(_ scalar: Double) {
        setVolumeValues.append(scalar)
    }
    func toggleMute() {
        toggleMuteCount += 1
    }
    func selectOutputDevice(_ deviceID: AudioDeviceID) {
        selectedOutputDeviceIDs.append(deviceID)
    }

    func setDetailsVisible(_ visible: Bool) {
        detailsVisibility.append(visible)
    }
    func send(_ value: VolumeStatus) { continuation.yield(value) }
}
