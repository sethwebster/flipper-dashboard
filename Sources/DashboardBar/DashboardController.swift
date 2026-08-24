import Combine
import FlipperIRCore
import Foundation

@MainActor
final class DashboardController: ObservableObject {
    enum State: Equatable {
        case checking
        case ready(String)
        case sending(String)
        case success(String)
        case failure(String)

        var message: String {
            switch self {
            case .checking:
                return "Refreshing saved operations…"
            case let .ready(device):
                return "Live on \(device)"
            case let .sending(operation):
                return "Sending \(operation)…"
            case let .success(operation):
                return "\(operation) sent"
            case let .failure(message):
                return message
            }
        }
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var snapshot: FlipperInventorySnapshot?
    @Published private(set) var isBusy = false

    private let inventoryService = FlipperInventoryService()
    private let subGHzService = FlipperSubGHzService()
    private var pollingTask: Task<Void, Never>?

    func startLiveUpdates() {
        pollingTask?.cancel()
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.refresh(silent: true)
            }
        }
    }

    func stopLiveUpdates() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh(silent: Bool = false) {
        guard !isBusy else { return }

        isBusy = true
        if !silent || snapshot == nil {
            state = .checking
        }

        Task {
            defer { isBusy = false }
            do {
                let result = try await inventoryService.inspect()
                snapshot = result
                state = .ready(Self.deviceName(from: result.port))
            } catch {
                state = .failure(error.localizedDescription)
            }
        }
    }

    func sendInfrared(remote: SavedInfraredRemote, signal: InfraredSignal) {
        guard !isBusy else { return }

        let operation = "\(remote.name) \(displayName(signal.name))"
        isBusy = true
        state = .sending(operation)

        Task {
            defer { isBusy = false }
            do {
                let service = FlipperIRService(remotePath: remote.path)
                _ = try await service.send(signalNamed: signal.name)
                state = .success(operation)
            } catch {
                state = .failure(error.localizedDescription)
            }
        }
    }

    func sendSubGHz(_ signal: SavedSubGHzSignal) {
        guard !isBusy else { return }

        let operation = "Sub-GHz \(signal.name)"
        isBusy = true
        state = .sending(operation)

        Task {
            defer { isBusy = false }
            do {
                try await subGHzService.transmit(filePath: signal.path)
                state = .success(operation)
            } catch {
                state = .failure(error.localizedDescription)
            }
        }
    }

    func displayName(_ storedName: String) -> String {
        storedName.replacingOccurrences(of: "_", with: " ")
    }

    private static func deviceName(from port: String) -> String {
        port.replacingOccurrences(of: "/dev/cu.usbmodemflip_", with: "Flipper ")
    }
}
