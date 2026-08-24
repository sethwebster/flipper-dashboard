import Darwin
import Foundation

public struct FlipperIRSnapshot: Sendable {
    public let port: String
    public let signals: [InfraredSignal]

    public var signalNames: Set<String> {
        Set(signals.map(\.name))
    }
}

public enum FlipperApplicationCoordinator {
    public static func ensureIdle(using session: FlipperCommanding) throws {
        for _ in 0..<3 {
            let loaderState = try session.command("loader info", timeout: 5)
            if loaderState.contains("No application is running") {
                return
            }
            guard loaderState.contains(" is running") else {
                throw FlipperSerialError.rejected("The Flipper returned an unknown loader state")
            }

            let closeResponse = try session.command("loader close", timeout: 5)
            if closeResponse.contains("No application is running") {
                return
            }
            guard closeResponse.contains("was closed") else {
                throw FlipperSerialError.rejected("The Flipper could not close its current app")
            }
            usleep(250_000)
        }

        throw FlipperSerialError.rejected("The app on the Flipper keeps reopening")
    }
}

public actor FlipperIRService {
    private let remotePath: String
    private var cachedRemote: InfraredRemote?

    public init(remotePath: String) {
        self.remotePath = remotePath
    }

    public func inspect() throws -> FlipperIRSnapshot {
        let session = try FlipperSerialSession()
        let remote = try loadRemote(using: session)
        cachedRemote = remote
        return snapshot(port: session.port, remote: remote)
    }

    public func send(signalNamed name: String) throws -> FlipperIRSnapshot {
        let session = try FlipperSerialSession()
        try FlipperApplicationCoordinator.ensureIdle(using: session)

        let remote: InfraredRemote
        if let cachedRemote {
            remote = cachedRemote
        } else {
            remote = try loadRemote(using: session)
            cachedRemote = remote
        }

        guard let signal = remote.signal(named: name) else {
            throw FlipperSerialError.rejected(
                "The stored remote does not contain \"\(name)\""
            )
        }

        let response = try session.command(signal.cliCommand, timeout: 15)
        try validateTransmissionResponse(response)
        return snapshot(port: session.port, remote: remote)
    }

    private func loadRemote(using session: FlipperSerialSession) throws -> InfraredRemote {
        guard
            remotePath.hasPrefix("/ext/infrared/"),
            remotePath.lowercased().hasSuffix(".ir"),
            !remotePath.contains("\r"),
            !remotePath.contains("\n")
        else {
            throw FlipperSerialError.rejected("Invalid saved infrared file path")
        }
        let output = try session.command("storage read \(remotePath)", timeout: 10)
        return try InfraredRemoteParser.parse(output)
    }

    private func validateTransmissionResponse(_ response: String) throws {
        let lowercased = response.lowercased()
        let rejectedMarkers = [
            "cannot be run",
            "invalid",
            "error",
            "usage:",
            "failed",
        ]
        if let marker = rejectedMarkers.first(where: lowercased.contains) {
            throw FlipperSerialError.rejected("The Flipper rejected the IR command: \(marker)")
        }
    }

    private func snapshot(port: String, remote: InfraredRemote) -> FlipperIRSnapshot {
        FlipperIRSnapshot(port: port, signals: remote.orderedSignals)
    }
}
