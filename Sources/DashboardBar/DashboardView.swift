import AppKit
import FlipperIRCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var controller: DashboardController

    private let actionColumns = [
        GridItem(.adaptive(minimum: 154), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pinnedSection
                    infraredSection
                    subGHzSection
                    savedDataSection
                }
            }
            .scrollIndicators(.never)

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 400, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Flipper Dashboard")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(controller.state.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if controller.isSending || (controller.isRefreshing && controller.snapshot == nil) {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if !controller.pinnedOperations.isEmpty {
            GroupBox {
                LazyVGrid(columns: actionColumns, spacing: 8) {
                    ForEach(controller.pinnedOperations) { operation in
                        operationButton(operation, name: operation.pinnedName)
                    }
                }
            } label: {
                Label("Pinned", systemImage: "pin.fill")
            }
        }
    }

    @ViewBuilder
    private var infraredSection: some View {
        if let remotes = controller.snapshot?.infraredRemotes, !remotes.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(remotes) { remote in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(remote.name)
                                .font(.subheadline.weight(.semibold))

                            LazyVGrid(columns: actionColumns, spacing: 8) {
                                ForEach(remote.signals) { signal in
                                    operationButton(
                                        .infrared(remote: remote, signal: signal)
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Infrared", systemImage: "light.beacon.max")
            }
        }
    }

    @ViewBuilder
    private var subGHzSection: some View {
        if let signals = controller.snapshot?.subGHzSignals, !signals.isEmpty {
            GroupBox {
                LazyVGrid(columns: actionColumns, spacing: 8) {
                    ForEach(signals) { signal in
                        operationButton(.subGHz(signal))
                    }
                }
            } label: {
                Label("Sub-GHz", systemImage: "wave.3.right")
            }
        }
    }

    @ViewBuilder
    private var savedDataSection: some View {
        if let snapshot = controller.snapshot {
            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    metricRow("NFC", value: snapshot.nfcFiles.count, icon: "wave.3.right.circle")
                    metricRow("LF RFID", value: snapshot.lowFrequencyRFIDFiles.count, icon: "key.horizontal")
                    metricRow("BadUSB scripts", value: snapshot.badUSBFiles.count, icon: "keyboard")
                    metricRow("Media files", value: snapshot.media.fileCount, icon: "photo.on.rectangle")
                    metricRow("Other files", value: snapshot.miscellaneousFiles.count, icon: "doc")
                    GridRow {
                        Label("Media storage", systemImage: "externaldrive")
                            .foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(snapshot.media.byteCount),
                            countStyle: .file
                        ))
                        .monospacedDigit()
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Saved data", systemImage: "internaldrive")
            }
        }
    }

    private func metricRow(_ title: String, value: Int, icon: String) -> some View {
        GridRow {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") {
                controller.refresh()
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing || controller.isSending)

            Spacer()

            Text("Live refresh: 60s")
                .foregroundStyle(.tertiary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var statusColor: Color {
        switch controller.state {
        case .ready, .success:
            return .green
        case .checking, .sending:
            return .orange
        case .failure:
            return .red
        }
    }

    private func operationButton(
        _ operation: DashboardOperation,
        name: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                controller.send(operation)
            } label: {
                Label(name ?? operation.shortName, systemImage: operation.systemImage)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(controller.isSending)

            Button {
                controller.togglePin(operation)
            } label: {
                Image(systemName: controller.isPinned(operation) ? "pin.fill" : "pin")
                    .font(.caption)
                    .foregroundStyle(
                        controller.isPinned(operation) ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(controller.isPinned(operation) ? "Unpin" : "Pin") \(operation.pinnedName)"
            )
            .help(controller.isPinned(operation) ? "Unpin" : "Pin to top")
        }
        .frame(maxWidth: .infinity)
    }
}
