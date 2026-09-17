import XCTest
@testable import MagSafeSMC

final class MagSafeSMCCommandTests: XCTestCase {
    func testCommandsExposeOnlyDocumentedACLCValues() {
        XCTAssertEqual(MagSafeLEDCommand.system.smcValue, 0)
        XCTAssertEqual(MagSafeLEDCommand.off.smcValue, 1)
    }

    func testSystemModeAcceptsSuccessfulWriteWhenSystemImmediatelyChangesReadback() {
        XCTAssertTrue(
            MagSafeSMC.didApplyLEDMode(
                .system,
                writeSucceeded: true,
                readValue: { 4 }
            )
        )
        XCTAssertFalse(
            MagSafeSMC.didApplyLEDMode(
                .system,
                writeSucceeded: false,
                readValue: { 0 }
            )
        )
    }

    func testOffModeStillRequiresMatchingReadback() {
        XCTAssertTrue(
            MagSafeSMC.didApplyLEDMode(
                .off,
                writeSucceeded: true,
                readValue: { 1 }
            )
        )
        XCTAssertFalse(
            MagSafeSMC.didApplyLEDMode(
                .off,
                writeSucceeded: true,
                readValue: { 4 }
            )
        )
    }

    func testOffModeWaitsForDelayedReadbackWithinOneRequest() {
        var values: [UInt8?] = [4, nil, 1]
        func nextValue() -> UInt8? { values.removeFirst() }

        XCTAssertTrue(MagSafeSMC.didApplyLEDMode(
            .off, writeSucceeded: true, readValue: { nextValue() }
        ))
        XCTAssertTrue(values.isEmpty)
    }

    func testFailedWriteCannotBeRescuedByMatchingReadback() {
        XCTAssertFalse(MagSafeSMC.didApplyLEDMode(
            .off, writeSucceeded: false, readValue: { 1 }
        ))
    }

    func testOffModeRejectsUnavailableReadback() {
        XCTAssertFalse(MagSafeSMC.didApplyLEDMode(
            .off, writeSucceeded: true, readValue: { nil }
        ))
    }

    func testXPCServiceForwardsOnlySupportedModes() {
        let recorder = MagSafeModeRecorder()
        let lifecycle = MagSafeLifecycleRecorder()
        let service = MagSafeLEDXPCService { command in
            recorder.commands.append(command)
            return true
        } requestDidBegin: {
            lifecycle.beginCount += 1
        } requestDidEnd: {
            lifecycle.endCount += 1
        }
        var offSucceeded = false
        var invalidSucceeded = true

        service.setLEDMode(MagSafeLEDCommand.off.rawValue) { offSucceeded = $0 }
        service.setLEDMode(2) { invalidSucceeded = $0 }

        XCTAssertTrue(offSucceeded)
        XCTAssertFalse(invalidSucceeded)
        XCTAssertEqual(recorder.commands, [.off])
        XCTAssertEqual(lifecycle.beginCount, 2)
        XCTAssertEqual(lifecycle.endCount, 2)
    }

    func testMachServiceNameFollowsBundleIdentifier() {
        XCTAssertEqual(
            MagSafeLEDXPC.serviceName(bundleIdentifier: "com.example.StatusTrio.dev"),
            "com.example.StatusTrio.dev.MagSafeHelper"
        )
    }
}

private final class MagSafeModeRecorder: @unchecked Sendable {
    var commands: [MagSafeLEDCommand] = []
}

private final class MagSafeLifecycleRecorder: @unchecked Sendable {
    var beginCount = 0
    var endCount = 0
}
