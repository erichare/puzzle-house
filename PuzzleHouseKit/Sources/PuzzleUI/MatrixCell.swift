import SwiftUI
import PuzzleScoring

/// A single completion-state cell in the Today matrix: a colored ring + glyph
/// (✓ / ✗ / –), with an accent ring marking the current user's column. Reusable
/// across the phone checklist and the iPad dashboard. Uniform 34×34 footprint so
/// columns line up regardless of state.
public struct MatrixCell: View {
    public let state: CompletionState
    public let isMe: Bool
    public let accessibilityName: String

    public init(state: CompletionState, isMe: Bool, accessibilityName: String) {
        self.state = state
        self.isMe = isMe
        self.accessibilityName = accessibilityName
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(state.borderColor, lineWidth: 1.5)
                .background(Circle().fill(state.fillColor))
                .frame(width: 28, height: 28)
            Text(glyph)
                .font(PuzzleFont.cellGlyph)
        }
        .frame(width: 34, height: 34)
        .overlay {
            if isMe {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 33, height: 33)
            }
        }
        .accessibilityLabel(Text("\(accessibilityName)\(isMe ? " (you)" : "") \(accessibilityState)"))
    }

    private var glyph: String {
        switch state {
        case .solved: return "✓"
        case .failed: return "✗"
        case .notPlayed: return "–"
        }
    }

    private var accessibilityState: String {
        switch state {
        case .solved: return "solved"
        case .failed: return "failed"
        case .notPlayed: return "not played"
        }
    }
}
