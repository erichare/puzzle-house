import SwiftUI

/// Reaction surface: animated count chips for existing reactions plus a wrapping
/// grid of the curated reaction set. Pure view — takes the current summary and
/// react/clear closures, so it has no `HouseholdStore` dependency. Selection and
/// count changes animate, and respect Reduce Motion.
public struct ReactionPicker: View {
    public let summary: [(emoji: String, count: Int)]
    public let myEmoji: String?
    public let canReact: Bool
    public let onReact: (String) -> Void
    public let onClear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        summary: [(emoji: String, count: Int)],
        myEmoji: String?,
        canReact: Bool,
        onReact: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.summary = summary
        self.myEmoji = myEmoji
        self.canReact = canReact
        self.onReact = onReact
        self.onClear = onClear
    }

    /// Curated reaction set — broader than the original six.
    public static let quickReactions = ["🔥", "🎉", "👏", "🤯", "😂", "❤️", "😮", "👀", "💪", "🥳", "🙌", "🤝"]

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 8)]

    public var body: some View {
        VStack(alignment: .leading, spacing: PuzzleSpacing.m) {
            if !summary.isEmpty {
                countChips
            }
            if canReact {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Self.quickReactions, id: \.self) { reactionButton($0) }
                    }
                }
                if myEmoji != nil {
                    Text("Tap your reaction again to remove it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var countChips: some View {
        HStack(spacing: PuzzleSpacing.s) {
            ForEach(summary, id: \.emoji) { pair in
                HStack(spacing: 4) {
                    Text(pair.emoji)
                    Text("\(pair.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    pair.emoji == myEmoji ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.10),
                    in: Capsule()
                )
            }
        }
        .puzzleAnimation(.snappy, value: summary.map { "\($0.emoji)\($0.count)" }, reduceMotion: reduceMotion)
    }

    private func reactionButton(_ emoji: String) -> some View {
        let isSelected = myEmoji == emoji
        return Button {
            Haptics.light()
            if isSelected { onClear() } else { onReact(emoji) }
        } label: {
            Text(emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor.opacity(0.55)).interactive() : .regular.interactive(),
            in: Circle()
        )
        .puzzleAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected, reduceMotion: reduceMotion)
        .accessibilityLabel(Text("React \(emoji)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
