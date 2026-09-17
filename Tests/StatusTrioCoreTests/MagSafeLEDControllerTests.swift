import XCTest
import MagSafeSMC
@testable import StatusTrioCore

@MainActor
final class MagSafeLEDControllerTests: XCTestCase {
    func testFileWriterReturnsOnlyAfterMatchingVerifiedAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioMagSafeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requestURL = directory.appendingPathComponent("request")
        let resultURL = directory.appendingPathComponent("result")
        let writer = FileMagSafeLEDCommandWriter(
            requestURL: requestURL,
            resultURL: resultURL,
            timeout: .seconds(1),
            retryInterval: .milliseconds(5)
        )
        let responder = Task.detached {
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: requestURL),
                   let text = String(data: data, encoding: .utf8),
                   let request = MagSafeLEDRequest(configuration: text) {
                    let result = MagSafeLEDResult(id: request.id, succeeded: true)
                    try Data(result.configuration.utf8).write(to: resultURL, options: .atomic)
                    return
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        try await writer.write(.off)
        responder.cancel()

        let requestData = try Data(contentsOf: requestURL)
        let requestText = String(decoding: requestData, as: UTF8.self)
        XCTAssertEqual(MagSafeLEDRequest(configuration: requestText)?.command, .off)
    }

    func testDefaultsToSystemControlAndPersistsSuccessfulOffCommand() async {
        let suite = makeSuite()
        defer { clear(suite) }
        let writer = RecordingMagSafeCommandWriter()
        let controller = makeController(defaults: suite.defaults, writer: writer)

        XCTAssertTrue(controller.isLightEnabled)

        controller.setLightEnabled(false)
        await waitUntilIdle(controller)

        XCTAssertFalse(controller.isLightEnabled)
        XCTAssertEqual(writer.modes, [.off])
        XCTAssertFalse(
            MagSafeLEDController(
                defaults: suite.defaults,
                hardwareProbe: SupportedMagSafeProbe(),
                helperManager: InstalledMagSafeHelperManager(),
                commandWriter: RecordingMagSafeCommandWriter()
            ).isLightEnabled
        )
    }

    func testFailedCommandDoesNotPublishOrPersistNewMode() async {
        let suite = makeSuite()
        defer { clear(suite) }
        let writer = RecordingMagSafeCommandWriter(error: TestFailure.write)
        let controller = makeController(defaults: suite.defaults, writer: writer)

        controller.setLightEnabled(false)
        await waitUntilIdle(controller)

        XCTAssertTrue(controller.isLightEnabled)
        XCTAssertEqual(controller.error, .writeFailed)
        XCTAssertNil(suite.defaults.object(forKey: MagSafeLEDController.defaultsKey))
    }

    func testReapplyWritesOnlyWhenStoredModeIsOffAndHelperIsReady() async {
        let suite = makeSuite()
        defer { clear(suite) }
        let writer = RecordingMagSafeCommandWriter()
        let controller = makeController(defaults: suite.defaults, writer: writer)

        controller.reapplyIfNeeded()
        XCTAssertTrue(writer.modes.isEmpty)

        controller.setLightEnabled(false)
        await waitUntilIdle(controller)
        writer.modes.removeAll()
        controller.reapplyIfNeeded()
        await waitUntilIdle(controller)

        XCTAssertEqual(writer.modes, [.off])
    }

    func testUnsupportedHardwareAndMissingHelperRemainDistinct() {
        let suite = makeSuite()
        defer { clear(suite) }

        let unsupported = MagSafeLEDController(
            defaults: suite.defaults,
            hardwareProbe: UnsupportedMagSafeProbe(),
            helperManager: InstalledMagSafeHelperManager(),
            commandWriter: RecordingMagSafeCommandWriter()
        )
        let missingHelper = MagSafeLEDController(
            defaults: suite.defaults,
            hardwareProbe: SupportedMagSafeProbe(),
            helperManager: MissingMagSafeHelperManager(),
            commandWriter: RecordingMagSafeCommandWriter()
        )

        XCTAssertEqual(unsupported.availability, .unsupported)
        XCTAssertEqual(missingHelper.availability, .needsInstallation)
    }

    func testInstallationPublishesRequiresApprovalState() async {
        let suite = makeSuite()
        defer { clear(suite) }
        let manager = RecordingMagSafeHelperManager(status: .notRegistered)
        manager.statusAfterInstall = .requiresApproval
        let controller = MagSafeLEDController(
            defaults: suite.defaults,
            hardwareProbe: SupportedMagSafeProbe(),
            helperManager: manager,
            commandWriter: RecordingMagSafeCommandWriter()
        )

        controller.installHelper()
        await waitUntilIdle(controller)

        XCTAssertEqual(manager.installCount, 1)
        XCTAssertEqual(controller.availability, .requiresApproval)
    }

    func testRegistrationErrorStillPublishesRequiresApprovalWhenServiceWasRegistered() async {
        let suite = makeSuite()
        defer { clear(suite) }
        let manager = RecordingMagSafeHelperManager(status: .notRegistered)
        manager.statusAfterInstall = .requiresApproval
        manager.installError = TestFailure.write
        let controller = MagSafeLEDController(
            defaults: suite.defaults,
            hardwareProbe: SupportedMagSafeProbe(),
            helperManager: manager,
            commandWriter: RecordingMagSafeCommandWriter()
        )

        controller.installHelper()
        await waitUntilIdle(controller)

        XCTAssertEqual(controller.availability, .requiresApproval)
        XCTAssertNil(controller.error)
    }

    func testUninstallDoesNotRemoveHelperWhenSystemResetFails() async {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(false, forKey: MagSafeLEDController.defaultsKey)
        let manager = RecordingMagSafeHelperManager(status: .enabled)
        let writer = RecordingMagSafeCommandWriter(error: TestFailure.write)
        let controller = MagSafeLEDController(
            defaults: suite.defaults,
            hardwareProbe: SupportedMagSafeProbe(),
            helperManager: manager,
            commandWriter: writer
        )

        controller.uninstallHelper()
        await waitUntilIdle(controller)

        XCTAssertEqual(manager.uninstallCount, 0)
        XCTAssertFalse(controller.isLightEnabled)
        XCTAssertEqual(controller.error, .uninstallFailed)
        XCTAssertEqual(controller.availability, .ready)
    }

    private func makeController(
        defaults: UserDefaults,
        writer: RecordingMagSafeCommandWriter
    ) -> MagSafeLEDController {
        MagSafeLEDController(
            defaults: defaults,
            hardwareProbe: SupportedMagSafeProbe(),
            helperManager: InstalledMagSafeHelperManager(),
            commandWriter: writer
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.MagSafeLED.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }

    private func waitUntilIdle(_ controller: MagSafeLEDController) async {
        while controller.isBusy {
            await Task.yield()
        }
    }
}

private enum TestFailure: Error {
    case write
}

private struct SupportedMagSafeProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool { true }
}

private struct UnsupportedMagSafeProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool { false }
}

private struct InstalledMagSafeHelperManager: MagSafeLEDHelperManaging {
    var status: MagSafeLEDHelperStatus { .enabled }

    func install() async throws {}
    func uninstall() async throws {}
    func openSystemSettings() {}
}

private struct MissingMagSafeHelperManager: MagSafeLEDHelperManaging {
    var status: MagSafeLEDHelperStatus { .notRegistered }

    func install() async throws {}
    func uninstall() async throws {}
    func openSystemSettings() {}
}

private final class RecordingMagSafeHelperManager: MagSafeLEDHelperManaging, @unchecked Sendable {
    var status: MagSafeLEDHelperStatus
    var statusAfterInstall: MagSafeLEDHelperStatus?
    var installError: Error?
    private(set) var installCount = 0
    private(set) var uninstallCount = 0

    init(status: MagSafeLEDHelperStatus) {
        self.status = status
    }

    func install() async throws {
        installCount += 1
        if let statusAfterInstall { status = statusAfterInstall }
        if let installError { throw installError }
    }

    func uninstall() async throws {
        uninstallCount += 1
        status = .notRegistered
    }

    func openSystemSettings() {}
}

private final class RecordingMagSafeCommandWriter: MagSafeLEDCommandWriting, @unchecked Sendable {
    var modes: [MagSafeLEDMode] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ mode: MagSafeLEDMode) async throws {
        if let error { throw error }
        modes.append(mode)
    }
}
