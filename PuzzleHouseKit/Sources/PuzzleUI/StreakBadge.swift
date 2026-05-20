import SwiftUI

public struct StreakBadge: View {
    public let count: Int
    public let label: String

    public init(count: Int, label: String) {
        self.count = count
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text("🔥")
            Text("\(count)").font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(.orange.opacity(0.45)), in: Capsule())
    }
}
