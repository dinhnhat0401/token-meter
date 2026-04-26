import SwiftUI

struct MenuBarLabel: View {
    let state: UsageState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var symbolName: String {
        if #available(macOS 14.0, *) {
            return "gauge.with.dots.needle.50percent"
        }
        return "gauge.medium"
    }

    private var tint: Color {
        guard let snapshot = state.snapshot else { return .secondary }
        let u = snapshot.headlineUtilization
        if u >= 0.85 { return .red }
        if u >= 0.60 { return .orange }
        return .secondary
    }

    private var label: String {
        switch state {
        case .loading: return "…"
        case .missingToken: return "—"
        case .ok(let s), .estimated(let s, _):
            let pct = Int((s.headlineUtilization * 100).rounded())
            return "\(pct)%"
        case .error: return "!"
        }
    }
}
