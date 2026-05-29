#if os(macOS)
import SwiftUI
import AppKit
import PuzzleCore
import PuzzleParsers
import PuzzleUI

/// Compact menu-bar quick-entry surface. Paste a result and submit without
/// opening the main window, see today's top of the leaderboard, and jump into
/// the full app. Lives in the package (`#if os(macOS)`) so it can reuse the
/// store, parsing, and `Avatar` directly. Presented by the app's `MenuBarExtra`.
public struct QuickEntryView: View {
    @Bindable var store: HouseholdStore
    let openMainWindow: () -> Void

    @State private var text = ""
    @State private var parsed: ParsedResult?
    @State private var phase: Phase = .editing

    private enum Phase: Equatable {
        case editing, saving, saved(String), failed(String)
    }

    public init(store: HouseholdStore, openMainWindow: @escaping () -> Void) {
        self.store = store
        self.openMainWindow = openMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            entryField
            statusLine
            controls
            if !store.leaderboard.isEmpty {
                Divider()
                leaderboard
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onChange(of: text) { _, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            parsed = trimmed.isEmpty ? nil : ParserRegistry.parse(trimmed)
            if phase != .saving { phase = .editing }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let household = store.selectedHousehold {
                Text(household.iconEmoji)
                Text(household.name).font(.headline).lineLimit(1)
            } else {
                Text("Puzzle House").font(.headline)
            }
            Spacer()
            Text("\(store.todayResults.count) today")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var entryField: some View {
        TextEditor(text: $text)
            .font(.system(.callout, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(height: 66)
            .padding(6)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .editing:
            if let parsed {
                Label("\(ParserRegistry.displayName(for: parsed.gameID) ?? parsed.gameID) #\(parsed.puzzleNumber)",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !text.isEmpty {
                Label("Not recognized yet", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Paste a Wordle, Connections, or Strands result")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .saving:
            Label("Saving\u{2026}", systemImage: "arrow.up.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .saved(let label):
            Label("Saved \(label)", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private var controls: some View {
        HStack {
            Button { pasteFromClipboard() } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .controlSize(.small)
            Spacer()
            Button { Task { await submit() } } label: {
                Text("Submit").frame(minWidth: 60)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(parsed == nil || phase == .saving)
        }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's household").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.leaderboard.prefix(3).enumerated()), id: \.element.userID) { idx, score in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption.bold()).foregroundStyle(.secondary).frame(width: 12)
                    Avatar(
                        emoji: store.avatarEmoji(for: score.userID),
                        displayName: store.displayName(for: score.userID),
                        size: 22,
                        photoData: store.avatarPhotoData(for: score.userID)
                    )
                    Text(store.displayName(for: score.userID)).font(.callout).lineLimit(1)
                    Spacer()
                    Text(String(format: "%+.2f", score.combined))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { openMainWindow() } label: {
                Label("Open Puzzle House", systemImage: "macwindow")
            }
            .controlSize(.small)
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Refresh from iCloud")
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            text = string
        }
    }

    private func submit() async {
        guard let parsed else { return }
        phase = .saving
        do {
            try await store.submit(parsed: parsed, rawPayload: text)
            let label = "\(ParserRegistry.displayName(for: parsed.gameID) ?? parsed.gameID) #\(parsed.puzzleNumber)"
            text = ""
            self.parsed = nil
            phase = .saved(label)
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
#endif
