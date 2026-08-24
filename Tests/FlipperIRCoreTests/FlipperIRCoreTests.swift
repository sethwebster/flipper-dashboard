import XCTest
@testable import FlipperIRCore

final class FlipperIRCoreTests: XCTestCase {
    func testParsesStorageListing() {
        let output = """
        storage list /ext/infrared\r
        \u{001B}[8C[D] assets\r
        \u{001B}[8C[F] Living_room.ir 1753b\r
        \u{001B}[8C[F] Receiver.ir 216b\r
        >:
        """

        let entries = FlipperStorageListingParser.parse(
            output,
            directory: "/ext/infrared"
        )

        guard entries.count == 3 else {
            XCTFail("Expected 3 entries, got \(entries.count)")
            return
        }
        XCTAssertEqual(entries[0].kind, .directory)
        XCTAssertEqual(entries[0].path, "/ext/infrared/assets")
        XCTAssertEqual(entries[1].name, "Living_room.ir")
        XCTAssertEqual(entries[1].byteCount, 1_753)
        XCTAssertEqual(entries[2].path, "/ext/infrared/Receiver.ir")
    }

    func testParsesSignalsInStoredOrder() throws {
        let output = """
        storage read /ext/infrared/Receiver.ir\r
        Size: 216\r
        Filetype: IR signals file
        \u{001B}[25CVersion: 1
        #
        name: Power
        type: parsed
        protocol: Samsung32
        address: 07 00 00 00
        command: E6 00 00 00
        #
        name: Mute
        type: parsed
        protocol: Samsung32
        address: 07 00 00 00
        command: 0F 00 00 00
        >:
        """

        let remote = try InfraredRemoteParser.parse(output)

        XCTAssertEqual(remote.orderedSignals.map(\.name), ["Power", "Mute"])
        XCTAssertEqual(remote.signal(named: "Power")?.cliCommand, "ir tx Samsung32 07 E6")
        XCTAssertEqual(remote.signal(named: "Mute")?.cliCommand, "ir tx Samsung32 07 0F")
    }

    func testParsesRawSignalAndBuildsCLICommand() throws {
        let output = """
        Filetype: IR signals file
        Version: 1
        #
        name: Power
        type: raw
        frequency: 38000
        duty_cycle: 0.330000
        data: 100 200 300 400
        """

        let remote = try InfraredRemoteParser.parse(output)

        XCTAssertEqual(
            remote.signal(named: "Power"),
            InfraredSignal(
                name: "Power",
                payload: .raw(
                    frequency: 38_000,
                    dutyCycle: 0.33,
                    samples: [100, 200, 300, 400]
                )
            )
        )
        XCTAssertEqual(
            remote.signal(named: "Power")?.cliCommand,
            "ir tx RAW F:38000 DC:33 100 200 300 400"
        )
    }

    func testCompactsMultiByteLittleEndianParsedFields() {
        let signal = InfraredSignal(
            name: "Example",
            payload: .parsed(
                protocolName: "NEC",
                address: "34 12 00 00",
                command: "CD AB 00 00"
            )
        )

        XCTAssertEqual(signal.cliCommand, "ir tx NEC 1234 ABCD")
    }

    func testRejectsRemoteWithoutSignals() {
        XCTAssertThrowsError(try InfraredRemoteParser.parse("Filetype: IR signals file\nVersion: 1")) { error in
            XCTAssertEqual(error as? InfraredRemoteParserError, .noSignals)
        }
    }

    func testConnectedFlipperCanReachIdleLoaderState() throws {
        try requireIntegrationTest()

        let session = try FlipperSerialSession()

        XCTAssertNoThrow(try FlipperApplicationCoordinator.ensureIdle(using: session))
    }

    func testConnectedFlipperInventoryUsesExpectedStorageRoots() async throws {
        try requireIntegrationTest()

        let snapshot = try await FlipperInventoryService().inspect()

        XCTAssertTrue(snapshot.port.hasPrefix("/dev/cu.usbmodemflip_"))
        XCTAssertTrue(snapshot.infraredRemotes.allSatisfy { $0.path.hasPrefix("/ext/infrared/") })
        XCTAssertTrue(snapshot.subGHzSignals.allSatisfy { $0.path.hasPrefix("/ext/subghz/") })
        XCTAssertTrue(snapshot.nfcFiles.allSatisfy { $0.path.hasPrefix("/ext/nfc/") })
        XCTAssertTrue(snapshot.lowFrequencyRFIDFiles.allSatisfy { $0.path.hasPrefix("/ext/lfrfid/") })
        XCTAssertTrue(snapshot.badUSBFiles.allSatisfy { $0.path.hasPrefix("/ext/badusb/") })
    }

    func testIdleCheckAcceptsApplicationThatAlreadyClosed() {
        let session = ScriptedCommandSession(responses: [
            "loader info\r\nApplication \"Infrared\" is running\r\n>: ",
            "loader close\r\nNo application is running\r\n>: ",
        ])

        XCTAssertNoThrow(try FlipperApplicationCoordinator.ensureIdle(using: session))
        XCTAssertEqual(session.commands, ["loader info", "loader close"])
    }

    func testIdleCheckRechecksAfterClosingAnApplication() {
        let session = ScriptedCommandSession(responses: [
            "loader info\r\nApplication \"Infrared\" is running\r\n>: ",
            "loader close\r\nApplication \"Infrared\" was closed\r\n>: ",
            "loader info\r\nNo application is running\r\n>: ",
        ])

        XCTAssertNoThrow(try FlipperApplicationCoordinator.ensureIdle(using: session))
        XCTAssertEqual(session.commands, ["loader info", "loader close", "loader info"])
    }

    func testIdleCheckHandlesApplicationReopeningOnce() {
        let session = ScriptedCommandSession(responses: [
            "loader info\r\nApplication \"Infrared\" is running\r\n>: ",
            "loader close\r\nApplication \"Infrared\" was closed\r\n>: ",
            "loader info\r\nApplication \"Infrared\" is running\r\n>: ",
            "loader close\r\nApplication \"Infrared\" was closed\r\n>: ",
            "loader info\r\nNo application is running\r\n>: ",
        ])

        XCTAssertNoThrow(try FlipperApplicationCoordinator.ensureIdle(using: session))
        XCTAssertEqual(
            session.commands,
            ["loader info", "loader close", "loader info", "loader close", "loader info"]
        )
    }

    private func requireIntegrationTest() throws {
        guard ProcessInfo.processInfo.environment["RUN_FLIPPER_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RUN_FLIPPER_INTEGRATION=1 to test a connected Flipper")
        }
    }
}

private final class ScriptedCommandSession: FlipperCommanding {
    private var responses: [String]
    private(set) var commands: [String] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func command(_ command: String, timeout: TimeInterval) throws -> String {
        commands.append(command)
        return responses.removeFirst()
    }
}
