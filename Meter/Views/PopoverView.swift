import SwiftUI

struct PopoverView: View {
    @ObservedObject var refresher: UsageRefresher
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text("Claude Code Usage")
                .font(.headline)
            Spacer()
            if refresher.state.snapshot?.source == .estimated {
                Text("estimated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch refresher.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .missingToken:
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Code not detected.")
                    .font(.subheadline).bold()
                Text("Run `claude` and sign in, then click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't read usage.")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        case .ok(let snapshot):
            snapshotView(snapshot, warning: nil)
        case .estimated(let snapshot, let underlying):
            snapshotView(snapshot, warning: underlying)
        }
    }

    private func snapshotView(_ snapshot: UsageSnapshot, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let five = snapshot.fiveHour {
                WindowRow(title: "5-hour window", window: five)
            } else if let tokens = snapshot.estimatedFiveHourTokens {
                EstimatedRow(title: "5-hour window", tokens: tokens)
            }

            if let seven = snapshot.sevenDay {
                WindowRow(title: "7-day window", window: seven)
            }

            if let warning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { refresher.refreshNow() }
                .buttonStyle(.borderless)
            Button("Quit") { onQuit() }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
    }

    private var footerText: String {
        guard let snapshot = refresher.state.snapshot else { return "" }
        let secs = Int(Date().timeIntervalSince(snapshot.capturedAt))
        if secs < 60 { return "Updated \(secs)s ago" }
        let mins = secs / 60
        return "Updated \(mins)m ago"
    }
}

private struct WindowRow: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(window.percent)% used")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(barColor)
            }
            ProgressView(value: min(window.utilization, 1.0))
                .progressViewStyle(.linear)
                .tint(barColor)
            if let resetText = resetCaption {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var barColor: Color {
        if window.isDanger { return .red }
        if window.isWarning { return .orange }
        return .accentColor
    }

    private var resetCaption: String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let now = Date()
        if resetsAt <= now { return "Resets now" }
        let interval = resetsAt.timeIntervalSince(now)
        return "Resets in \(formatDuration(interval))"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private struct EstimatedRow: View {
    let title: String
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(tokens) tokens")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Estimated locally — couldn't reach Anthropic API")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
