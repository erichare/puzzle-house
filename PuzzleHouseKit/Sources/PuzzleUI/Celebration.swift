import SwiftUI

/// A milestone worth a moment — a newly-unlocked achievement, a kept streak, a
/// daily house win. Produced by the store, rendered by `CelebrationOverlay`.
public struct Celebration: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let glyph: String

    public init(id: String, title: String, message: String, glyph: String) {
        self.id = id
        self.title = title
        self.message = message
        self.glyph = glyph
    }
}

/// Celebratory overlay. Springs in with a success haptic; under Reduce Motion it
/// fades in statically (no scale/spring). Tap the scrim or button to dismiss.
public struct CelebrationOverlay: View {
    public let celebration: Celebration
    public let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(celebration: Celebration, onDismiss: @escaping () -> Void) {
        self.celebration = celebration
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: PuzzleSpacing.l) {
                Image(systemName: celebration.glyph)
                    .font(.system(size: 64))
                    .symbolRenderingMode(.multicolor)
                    .scaleEffect(showsMotion && !appeared ? 0.5 : 1)
                Text(celebration.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(celebration.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Nice!") { onDismiss() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding(PuzzleSpacing.xxl)
            .frame(maxWidth: 360)
            .puzzleCard()
            .padding(PuzzleSpacing.xl)
            .scaleEffect(showsMotion && !appeared ? 0.8 : 1)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Haptics.celebrate()
            if showsMotion {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
            } else {
                appeared = true
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(celebration.title). \(celebration.message)"))
    }

    private var showsMotion: Bool { !reduceMotion }
}
