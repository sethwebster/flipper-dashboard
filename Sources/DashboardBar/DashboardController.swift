import Combine
import FlipperIRCore
import Foundation

@MainActor
final class DashboardController: ObservableObject {
    typealias InventoryLoader = @Sendable () async throws -> FlipperInventorySnapshot

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
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSending = false
    @Published private(set) var pinnedOperationIDs: [String]

    var pinnedOperations: [DashboardOperation] {
        let operationsByID = Dictionary(
            uniqueKeysWithValues: allOperations.map { ($0.id, $0) }
        )
        return pinnedOperationIDs.compactMap { operationsByID[$0] }
    }

    private static let pinnedOperationsKey = "PinnedOperationIDs"

    private let defaults: UserDefaults
    private let loadInventory: InventoryLoader
    private let pollInterval: Duration
    private let subGHzService = FlipperSubGHzService()
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        pollInterval: Duration = .seconds(60),
        loadInventory: @escaping InventoryLoader = {
            let scan = Task.detached(priority: .utility) {
                try FlipperInventoryService().inspect()
            }
            return try await withTaskCancellationHandler {
                try await scan.value
            } onCancel: {
                scan.cancel()
            }
        }
    ) {
        self.defaults = defaults
        self.pollInterval = pollInterval
        self.loadInventory = loadInventory
        pinnedOperationIDs = defaults.stringArray(
            forKey: Self.pinnedOperationsKey
        ) ?? []
    }

    func startLiveUpdates() {
        pollingTask?.cancel()
        refresh()
        pollingTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                self?.refresh(silent: true)
            }
        }
    }

    func stopLiveUpdates() {
        pollingTask?.cancel()
        pollingTask = nil
        refreshTask?.cancel()
    }

    func refresh(silent: Bool = false) {
        guard !isRefreshing, !isSending else { return }

        isRefreshing = true
        if !silent || snapshot == nil {
            state = .checking
        }

        refreshTask = Task { [weak self, loadInventory] in
            defer {
                self?.isRefreshing = false
                self?.refreshTask = nil
            }

            do {
                let result = try await loadInventory()
                try Task.checkCancellation()
                guard let self else { return }
                snapshot = result
                state = .ready(Self.deviceName(from: result.port))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failure(error.localizedDescription)
            }
        }
    }

    func send(_ operation: DashboardOperation) {
        guard !isSending else { return }

        isSending = true
        state = .sending(operation.statusName)

        let pendingRefresh = refreshTask
        pendingRefresh?.cancel()

        sendTask = Task { [weak self] in
            _ = await pendingRefresh?.result
            guard let self else { return }

            defer {
                isSending = false
                sendTask = nil
            }

            do {
                switch operation {
                case let .infrared(remote, signal):
                    let service = FlipperIRService(remotePath: remote.path)
                    _ = try await service.send(signalNamed: signal.name)
                case let .subGHz(signal):
                    try await subGHzService.transmit(filePath: signal.path)
                }
                state = .success(operation.statusName)
            } catch {
                state = .failure(error.localizedDescription)
            }
        }
    }

    func isPinned(_ operation: DashboardOperation) -> Bool {
        pinnedOperationIDs.contains(operation.id)
    }

    func togglePin(_ operation: DashboardOperation) {
        togglePin(id: operation.id)
    }

    func togglePin(id: String) {
        if let index = pinnedOperationIDs.firstIndex(of: id) {
            pinnedOperationIDs.remove(at: index)
        } else {
            pinnedOperationIDs.append(id)
        }
        defaults.set(pinnedOperationIDs, forKey: Self.pinnedOperationsKey)
    }

    private var allOperations: [DashboardOperation] {
        guard let snapshot else { return [] }

        let infrared = snapshot.infraredRemotes.flatMap { remote in
            remote.signals.map { signal in
                DashboardOperation.infrared(remote: remote, signal: signal)
            }
        }
        let subGHz = snapshot.subGHzSignals.map(DashboardOperation.subGHz)
        return infrared + subGHz
    }

    private static func deviceName(from port: String) -> String {
        port.replacingOccurrences(of: "/dev/cu.usbmodemflip_", with: "Flipper ")
    }
}
