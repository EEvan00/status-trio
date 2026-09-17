import XCTest
@testable import MagSafeSMC

final class MagSafeSMCCommandTests: XCTestCase {
    func testConfigurationAcceptsOnlySystemAndOffCommands() {
        XCTAssertEqual(MagSafeLEDCommand(configuration: "system\n"), .system)
        XCTAssertEqual(MagSafeLEDCommand(configuration: "off\n"), .off)

        for invalid in ["", "green\n", "off now\n", "system\noff\n", "1\n"] {
            XCTAssertNil(MagSafeLEDCommand(configuration: invalid), invalid)
        }
    }

    func testCommandsExposeOnlyDocumentedACLCValues() {
        XCTAssertEqual(MagSafeLEDCommand.system.smcValue, 0)
        XCTAssertEqual(MagSafeLEDCommand.off.smcValue, 1)
    }

    func testSystemModeAcceptsSuccessfulWriteWhenSystemImmediatelyChangesReadback() {
        XCTAssertTrue(
            MagSafeSMC.didApplyLEDMode(
                .system,
                writeSucceeded: true,
                readValue: 4
            )
        )
        XCTAssertFalse(
            MagSafeSMC.didApplyLEDMode(
                .system,
                writeSucceeded: false,
                readValue: 0
            )
        )
    }

    func testOffModeStillRequiresMatchingReadback() {
        XCTAssertTrue(
            MagSafeSMC.didApplyLEDMode(
                .off,
                writeSucceeded: true,
                readValue: 1
            )
        )
        XCTAssertFalse(
            MagSafeSMC.didApplyLEDMode(
                .off,
                writeSucceeded: true,
                readValue: 4
            )
        )
    }

    func testRequestAndResultRoundTripWithMatchingIdentifier() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let request = MagSafeLEDRequest(id: id, command: .off)
        let result = MagSafeLEDResult(id: id, succeeded: true)

        XCTAssertEqual(MagSafeLEDRequest(configuration: request.configuration), request)
        XCTAssertEqual(MagSafeLEDResult(configuration: result.configuration), result)
    }

    func testRequestAndResultRejectMalformedPayloads() {
        for invalid in ["", "off\n", "not-a-uuid off\n", "12345678-1234-1234-1234-123456789ABC green\n"] {
            XCTAssertNil(MagSafeLEDRequest(configuration: invalid), invalid)
        }
        for invalid in ["", "ok\n", "not-a-uuid ok\n", "12345678-1234-1234-1234-123456789ABC maybe\n"] {
            XCTAssertNil(MagSafeLEDResult(configuration: invalid), invalid)
        }
    }

    func testConsumingRequestRemovesWatchedPathBeforeReturning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioSMCRequestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requestURL = directory.appendingPathComponent("request")
        let expected = MagSafeLEDRequest(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            command: .off
        )
        try Data(expected.configuration.utf8).write(to: requestURL)

        let request = try MagSafeLEDRequestFile.consume(at: requestURL)

        XCTAssertEqual(request, expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL.path))
    }

    func testConsumingMalformedRequestStillRemovesWatchedPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioSMCRequestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requestURL = directory.appendingPathComponent("request")
        try Data("malformed\n".utf8).write(to: requestURL)

        XCTAssertThrowsError(try MagSafeLEDRequestFile.consume(at: requestURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL.path))
    }
}
