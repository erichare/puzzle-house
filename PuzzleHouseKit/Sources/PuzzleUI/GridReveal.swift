import SwiftUI

public struct GridReveal: View {
    public let gridData: String?
    public let isHidden: Bool

    public init(gridData: String?, isHidden: Bool) {
        self.gridData = gridData
        self.isHidden = isHidden
    }

    public var body: some View {
        if isHidden {
            // Only show the spoiler placeholder when the viewer is locked out
            // of someone else's result. If the result simply has no grid
            // (e.g. Emoji Game), render nothing — the score block carries
            // the information.
            placeholder
        } else if let grid = gridData, !grid.isEmpty {
            Text(grid)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
        }
    }

    private var placeholder: some View {
        Label("Hidden until you play", systemImage: "eye.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}
