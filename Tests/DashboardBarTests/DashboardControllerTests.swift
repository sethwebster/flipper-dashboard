import Foundation
import XCTest
@testable import DashboardBar
@testable import FlipperIRCore

@MainActor
final class DashboardControllerTests: XCTestCase {
    func testSilentRefreshDoesNotDisableOperations() {
        let controller = DashboardController(loadInventory: {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        })

        controller.refresh(silent: true)

        XCTAssertTrue(controller.isRefreshing)
        XCTAssertFalse(controller.isSending)
        controller.stopLiveUpdates()
    }

    func testPinsPersistInPinOrder() throws {
        let suiteName = "DashboardControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = DashboardController(defaults: defaults)
        controller.togglePin(id: "infrared:first")
        controller.togglePin(id: "subghz:second")

        XCTAssertEqual(
            controller.pinnedOperationIDs,
            ["infrared:first", "subghz:second"]
        )

        let restored = DashboardController(defaults: defaults)
        XCTAssertEqual(
            restored.pinnedOperationIDs,
            ["infrared:first", "subghz:second"]
        )

        restored.togglePin(id: "infrared:first")
        XCTAssertEqual(restored.pinnedOperationIDs, ["subghz:second"])
    }

    func testPinnedOperationsRenderInPinOrder() async throws {
        let suiteName = "DashboardControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let remote = SavedInfraredRemote(
            path: "/ext/infrared/Living_room.ir",
            signals: [
                InfraredSignal(
                    name: "Power",
                    payload: .parsed(
                        protocolName: "NEC",
                        address: "00 00 00 00",
                        command: "01 00 00 00"
                    )
                ),
            ]
        )
        let subGHz = SavedSubGHzSignal(
            path: "/ext/subghz/Door.sub",
            name: "Door",
            byteCount: 128
        )
        let snapshot = FlipperInventorySnapshot(
            port: "/dev/cu.usbmodemflip_test",
            infraredRemotes: [remote],
            subGHzSignals: [subGHz],
            nfcFiles: [],
            lowFrequencyRFIDFiles: [],
            badUSBFiles: [],
            miscellaneousFiles: [],
            media: FlipperMediaSummary(fileCount: 0, byteCount: 0)
        )
        let controller = DashboardController(
            defaults: defaults,
            loadInventory: { snapshot }
        )

        controller.refresh()
        while controller.isRefreshing {
            await Task.yield()
        }

        let subGHzID = "subghz:/ext/subghz/Door.sub"
        let infraredID = "infrared:/ext/infrared/Living_room.ir#Power"
        controller.togglePin(id: subGHzID)
        controller.togglePin(id: infraredID)

        XCTAssertEqual(
            controller.pinnedOperations.map(\.id),
            [subGHzID, infraredID]
        )
    }
}
