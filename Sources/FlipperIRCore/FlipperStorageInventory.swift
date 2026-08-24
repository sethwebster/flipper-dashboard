import Foundation

public enum FlipperStorageEntryKind: Equatable, Sendable {
    case file
    case directory
}

public struct FlipperStorageEntry: Identifiable, Sendable {
    public let path: String
    public let name: String
    public let kind: FlipperStorageEntryKind
    public let byteCount: Int?

    public var id: String { path }
}

public struct SavedInfraredRemote: Identifiable, Sendable {
    public let path: String
    public let signals: [InfraredSignal]

    public var id: String { path }

    public var name: String {
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return filename.replacingOccurrences(of: "_", with: " ")
    }
}

public struct SavedSubGHzSignal: Identifiable, Sendable {
    public let path: String
    public let name: String
    public let byteCount: Int

    public var id: String { path }
}

public struct FlipperMediaSummary: Sendable {
    public let fileCount: Int
    public let byteCount: Int
}

public struct FlipperInventorySnapshot: Sendable {
    public let port: String
    public let infraredRemotes: [SavedInfraredRemote]
    public let subGHzSignals: [SavedSubGHzSignal]
    public let nfcFiles: [FlipperStorageEntry]
    public let lowFrequencyRFIDFiles: [FlipperStorageEntry]
    public let badUSBFiles: [FlipperStorageEntry]
    public let miscellaneousFiles: [FlipperStorageEntry]
    public let media: FlipperMediaSummary
}

public enum FlipperStorageListingParser {
    public static func parse(_ output: String, directory: String) -> [FlipperStorageEntry] {
        let cleanedOutput = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )

        return cleanedOutput
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n")
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = line.wholeMatch(of: /^\[F\]\s+(.+?)\s+(\d+)b$/),
                   let byteCount = Int(match.2) {
                    let name = String(match.1)
                    return FlipperStorageEntry(
                        path: directory + "/" + name,
                        name: name,
                        kind: .file,
                        byteCount: byteCount
                    )
                }

                if let match = line.wholeMatch(of: /^\[D\]\s+(.+)$/) {
                    let name = String(match.1)
                    return FlipperStorageEntry(
                        path: directory + "/" + name,
                        name: name,
                        kind: .directory,
                        byteCount: nil
                    )
                }

                return nil
            }
    }
}

public actor FlipperInventoryService {
    public init() {}

    public func inspect() throws -> FlipperInventorySnapshot {
        let session = try FlipperSerialSession()

        let infraredEntries = try filesRecursively(in: "/ext/infrared", using: session)
        var infraredRemotes: [SavedInfraredRemote] = []
        for entry in infraredEntries where entry.name.lowercased().hasSuffix(".ir") {
            do {
                let output = try session.command("storage read \(entry.path)", timeout: 10)
                let remote = try InfraredRemoteParser.parse(output)
                infraredRemotes.append(
                    SavedInfraredRemote(path: entry.path, signals: remote.orderedSignals)
                )
            } catch is InfraredRemoteParserError {
                continue
            }
        }

        let subGHzSignals = try filesRecursively(in: "/ext/subghz", using: session)
            .filter { $0.name.lowercased().hasSuffix(".sub") }
            .map { entry in
                SavedSubGHzSignal(
                    path: entry.path,
                    name: URL(fileURLWithPath: entry.name).deletingPathExtension().lastPathComponent,
                    byteCount: entry.byteCount ?? 0
                )
            }

        let nfcFiles = try filesRecursively(in: "/ext/nfc", using: session)
        let rfidFiles = try filesRecursively(in: "/ext/lfrfid", using: session)
        let badUSBFiles = try filesRecursively(in: "/ext/badusb", using: session)
        let miscellaneousFiles = try filesRecursively(in: "/ext/MISC", using: session)

        let mediaFiles = try filesRecursively(in: "/ext/DCIM", using: session)
        let media = FlipperMediaSummary(
            fileCount: mediaFiles.count,
            byteCount: mediaFiles.reduce(0) { $0 + ($1.byteCount ?? 0) }
        )

        return FlipperInventorySnapshot(
            port: session.port,
            infraredRemotes: infraredRemotes,
            subGHzSignals: subGHzSignals,
            nfcFiles: nfcFiles,
            lowFrequencyRFIDFiles: rfidFiles,
            badUSBFiles: badUSBFiles,
            miscellaneousFiles: miscellaneousFiles,
            media: media
        )
    }

    private func list(
        _ directory: String,
        using session: FlipperSerialSession
    ) throws -> [FlipperStorageEntry] {
        let output = try session.command("storage list \(directory)", timeout: 15)
        if output.contains("Storage error:") {
            return []
        }
        return FlipperStorageListingParser.parse(output, directory: directory)
    }

    private func filesRecursively(
        in directory: String,
        remainingDepth: Int = 8,
        using session: FlipperSerialSession
    ) throws -> [FlipperStorageEntry] {
        guard remainingDepth >= 0 else { return [] }

        let entries = try list(directory, using: session)
        var files = entries.filter { $0.kind == .file }
        for child in entries where child.kind == .directory {
            files += try filesRecursively(
                in: child.path,
                remainingDepth: remainingDepth - 1,
                using: session
            )
        }
        return files.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }
}
