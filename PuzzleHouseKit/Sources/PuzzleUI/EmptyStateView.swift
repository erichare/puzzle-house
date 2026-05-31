import SwiftUI

/// A friendly, illustrated empty / first-run state. Replaces ad-hoc
/// `ContentUnavailableView` usages with a consistent layered-symbol treatment
/// built on the design-system tokens, with an optional call-to-action.
public struct PuzzleEmptyState: View {
    public let symbol: String
    public let title: String
    public let message: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: PuzzleSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .padding(.bottom, PuzzleSpacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .font(PuzzleFont.sectionHeader)
                .multilineTextAlignment(.center)
            Text(message)
                .font(PuzzleFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .padding(.top, PuzzleSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PuzzleSpacing.xxxl)
        .padding(.horizontal, PuzzleSpacing.l)
    }
}
