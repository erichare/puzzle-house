import SwiftUI

public struct GridReveal: View {
    public let gridData: String?
    public let isHidden: Bool

    public init(gridData: String?, isHidden: Bool) {
        self.gridData = gridData
        self.isHidden = isHidden
    }

    public var body: some View {
        if isHidden || gridData == nil {
            placeholder
        } else if let grid = gridData {
            Text(grid)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PuzzleTheme.secondaryFill)
            .frame(height: 80)
            .overlay(
                Label("Hidden until you play", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
}
