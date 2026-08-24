import Foundation

public struct InfraredRemote: Sendable {
    public let orderedSignals: [InfraredSignal]
    public let signals: [String: InfraredSignal]

    public init(orderedSignals: [InfraredSignal]) {
        self.orderedSignals = orderedSignals
        signals = Dictionary(uniqueKeysWithValues: orderedSignals.map { ($0.name, $0) })
    }

    public func signal(named name: String) -> InfraredSignal? {
        signals[name]
    }
}

public struct InfraredSignal: Equatable, Identifiable, Sendable {
    public let name: String
    public let payload: Payload

    public var id: String { name }

    public init(name: String, payload: Payload) {
        self.name = name
        self.payload = payload
    }

    public enum Payload: Equatable, Sendable {
        case raw(frequency: Int, dutyCycle: Double, samples: [Int])
        case parsed(protocolName: String, address: String, command: String)
    }

    public var cliCommand: String {
        switch payload {
        case let .raw(frequency, dutyCycle, samples):
            let dutyPercent = Int((dutyCycle * 100).rounded())
            let sampleText = samples.map(String.init).joined(separator: " ")
            return "ir tx RAW F:\(frequency) DC:\(dutyPercent) \(sampleText)"
        case let .parsed(protocolName, address, command):
            return "ir tx \(protocolName) \(Self.compactHex(address)) \(Self.compactHex(command))"
        }
    }

    private static func compactHex(_ fileValue: String) -> String {
        var littleEndianBytes = fileValue
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).uppercased() }

        while littleEndianBytes.count > 1, littleEndianBytes.last == "00" {
            littleEndianBytes.removeLast()
        }

        return littleEndianBytes.reversed().joined()
    }
}

public enum InfraredRemoteParserError: LocalizedError, Equatable {
    case noSignals
    case malformedSignal(String)

    public var errorDescription: String? {
        switch self {
        case .noSignals:
            return "The infrared remote contains no readable signals"
        case let .malformedSignal(name):
            return "The infrared signal \"\(name)\" is incomplete"
        }
    }
}

public enum InfraredRemoteParser {
    public static func parse(_ output: String) throws -> InfraredRemote {
        let cleanedOutput = stripTerminalFormatting(from: output)
        let lines = cleanedOutput
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var fields: [String: String] = [:]
        var orderedSignals: [InfraredSignal] = []

        func makeSignal(from values: [String: String]) throws -> InfraredSignal? {
            guard let name = values["name"], !name.isEmpty else {
                return nil
            }

            switch values["type"]?.lowercased() {
            case "raw":
                guard
                    let frequencyText = values["frequency"],
                    let frequency = Int(frequencyText),
                    let dutyText = values["duty_cycle"],
                    let dutyCycle = Double(dutyText),
                    let dataText = values["data"]
                else {
                    throw InfraredRemoteParserError.malformedSignal(name)
                }

                let samples = dataText
                    .split(whereSeparator: { $0.isWhitespace })
                    .compactMap { Int($0) }
                guard !samples.isEmpty else {
                    throw InfraredRemoteParserError.malformedSignal(name)
                }

                return InfraredSignal(
                    name: name,
                    payload: .raw(
                        frequency: frequency,
                        dutyCycle: dutyCycle,
                        samples: samples
                    )
                )

            case "parsed":
                guard
                    let protocolName = values["protocol"],
                    let address = values["address"],
                    let command = values["command"]
                else {
                    throw InfraredRemoteParserError.malformedSignal(name)
                }

                return InfraredSignal(
                    name: name,
                    payload: .parsed(
                        protocolName: protocolName,
                        address: address,
                        command: command
                    )
                )

            default:
                throw InfraredRemoteParserError.malformedSignal(name)
            }
        }

        func storeCurrentSignal() throws {
            if let signal = try makeSignal(from: fields) {
                if let index = orderedSignals.firstIndex(where: { $0.name == signal.name }) {
                    orderedSignals[index] = signal
                } else {
                    orderedSignals.append(signal)
                }
            }
            fields.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line == "#" {
                try storeCurrentSignal()
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        try storeCurrentSignal()

        guard !orderedSignals.isEmpty else {
            throw InfraredRemoteParserError.noSignals
        }
        return InfraredRemote(orderedSignals: orderedSignals)
    }

    private static func stripTerminalFormatting(from output: String) -> String {
        let ansiPattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
        let withoutANSI = output.replacingOccurrences(
            of: ansiPattern,
            with: "",
            options: .regularExpression
        )

        let scalars = withoutANSI.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar.value >= 32
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
