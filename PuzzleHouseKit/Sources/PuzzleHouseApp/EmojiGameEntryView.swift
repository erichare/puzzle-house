import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import PuzzleCore
import PuzzleParsers

/// Manual entry for Apple News' Emoji Game.
///
/// The game shares only an opaque `apple.news` link (no score), and Vision
/// can't reliably read its emoji grid from a screenshot — so the most accurate
/// capture is simply to ask the player how many moves they took. `6` is the
/// fewest possible ("Perfect"); every wrong guess or revealed clue adds one.
///
/// The view stays deliberately thin: it builds an `EmojiGameParser` payload via
/// the shared helpers and hands the parsed result back through `onSubmit`, so
/// all scoring/identity logic lives in the parser (and is unit-tested there).
public struct EmojiGameEntryView: View {
    @State private var moves: Double
    @State private var isSubmitting = false
    @State private var error: String?

    private let game = Game.emojiGame
    private let lowerBound = Double(EmojiGameParser.perfectMoves)   // 6 = Perfect
    private let upperBound = 20.0

    let onSubmit: @MainActor (ParsedResult, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        initialMoves: Int = EmojiGameParser.perfectMoves,
        onSubmit: @escaping @MainActor (ParsedResult, String) async throws -> Void
    ) {
        _moves = State(initialValue: Double(initialMoves))
        self.onSubmit = onSubmit
    }

    private var moveCount: Int { Int(moves.rounded()) }
    private var isPerfect: Bool { moveCount <= EmojiGameParser.perfectMoves }

    public var body: some View {
        NavigationStack {
            Form {
                Section { tally }
                Section {
                    slider
                } header: {
                    Text("How many moves did you take?")
                } footer: {
                    Text("Apple News only shares a link, so log your result here. 6 is the fewest possible (\u{201C}Perfect\u{201D}); each wrong guess or revealed clue adds one.")
                }
                if isSubmitting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Saving to iCloud\u{2026}").foregroundStyle(.secondary)
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Emoji Game")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSubmitting)
                }
            }
        }
    }

    private var tally: some View {
        VStack(spacing: 10) {
            Text(game.emoji).font(.system(size: 52))
            Text("\(moveCount)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: moveCount)
            Text(isPerfect ? "Perfect! 🎉" : "\(moveCount) moves")
                .font(.headline)
                .foregroundStyle(isPerfect ? Color.accentColor : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var slider: some View {
        Slider(value: $moves, in: lowerBound...upperBound, step: 1) {
            Text("Moves")
        } minimumValueLabel: {
            Text("6").font(.caption).foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("20+").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: moves) { _, _ in
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }

    private func save() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let number = EmojiGameParser.puzzleNumber(for: Date(), in: .current)
        let payload = EmojiGameParser.movesPayload(puzzleNumber: number, moves: moveCount)
        guard let parsed = ParserRegistry.parse(payload) else {
            error = "Couldn't build the result. Please try again."
            return
        }
        do {
            try await onSubmit(parsed, payload)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            dismiss()
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            self.error = String(describing: error)
        }
    }
}
