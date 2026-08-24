import Foundation

public actor FlipperSubGHzService {
    public init() {}

    public func transmit(filePath: String) throws {
        guard
            filePath.hasPrefix("/ext/subghz/"),
            filePath.lowercased().hasSuffix(".sub"),
            !filePath.contains("\r"),
            !filePath.contains("\n")
        else {
            throw FlipperSerialError.rejected("Invalid saved Sub-GHz file path")
        }

        let session = try FlipperSerialSession()
        try FlipperApplicationCoordinator.ensureIdle(using: session)
        let response = try session.command(
            "subghz tx_from_file \(filePath) 1 0",
            timeout: 60
        )

        guard response.contains("Listening at"), response.contains("Frequency=") else {
            throw FlipperSerialError.rejected("The Flipper did not confirm the Sub-GHz transmission")
        }
    }
}
