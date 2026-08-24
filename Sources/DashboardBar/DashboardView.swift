import AppKit
import FlipperIRCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var controller: DashboardController

    private let actionColumns = [
        GridItem(.adaptive(minimum: 104), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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

            if controller.isBusy {
                ProgressView()
                    .controlSize(.small)
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
                                    Button {
                                        controller.sendInfrared(remote: remote, signal: signal)
                                    } label: {
                                        Label(
                                            controller.displayName(signal.name),
                                            systemImage: infraredIcon(for: signal.name)
                                        )
                                        .frame(maxWidth: .infinity, minHeight: 28)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(controller.isBusy)
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
                        Button {
                            controller.sendSubGHz(signal)
                        } label: {
                            Label(signal.name, systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.bordered)
                        .disabled(controller.isBusy)
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
            .disabled(controller.isBusy)

            Spacer()

            Text("Live refresh: 15s")
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

    private func infraredIcon(for name: String) -> String {
        switch name.lowercased() {
        case "power": "power"
        case "mute": "speaker.slash.fill"
        case "speed_up": "plus"
        case "speed_down": "minus"
        default: "button.programmable"
        }
    }
}
