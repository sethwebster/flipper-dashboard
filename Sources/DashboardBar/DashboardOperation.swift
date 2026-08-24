import FlipperIRCore

enum DashboardOperation: Identifiable, Sendable {
    case infrared(remote: SavedInfraredRemote, signal: InfraredSignal)
    case subGHz(SavedSubGHzSignal)

    var id: String {
        switch self {
        case let .infrared(remote, signal):
            return "infrared:\(remote.path)#\(signal.name)"
        case let .subGHz(signal):
            return "subghz:\(signal.path)"
        }
    }

    var shortName: String {
        switch self {
        case let .infrared(_, signal):
            return Self.displayName(signal.name)
        case let .subGHz(signal):
            return signal.name
        }
    }

    var pinnedName: String {
        switch self {
        case let .infrared(remote, signal):
            return "\(remote.name) \(Self.displayName(signal.name))"
        case let .subGHz(signal):
            return "Sub-GHz \(signal.name)"
        }
    }

    var statusName: String { pinnedName }

    var systemImage: String {
        switch self {
        case let .infrared(_, signal):
            switch signal.name.lowercased() {
            case "power": return "power"
            case "mute": return "speaker.slash.fill"
            case "speed_up": return "plus"
            case "speed_down": return "minus"
            default: return "button.programmable"
            }
        case .subGHz:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private static func displayName(_ storedName: String) -> String {
        storedName.replacingOccurrences(of: "_", with: " ")
    }
}
