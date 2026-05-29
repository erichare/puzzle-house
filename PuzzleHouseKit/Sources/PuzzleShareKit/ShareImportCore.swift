import Foundation
import UniformTypeIdentifiers
import PuzzleCore
import PuzzleParsers
import PuzzleCloudKit

/// Status of a share-extension import, surfaced by `ShareStatusView`.
public enum ShareImportStatus: Equatable, Sendable {
    case loading
    case success(message: String)
    case failure(message: String)
}

/// Platform-neutral share-extension logic shared by the iOS and macOS Share
/// extensions: read text from the shared item providers, reject Apple News
/// links, parse the result, and enqueue it into the offline write queue (the
/// main app drains the queue on next launch). Keeping this in the package means
/// both extension shells behave identically and never drift.
public enum ShareImportCore {

    public static func isAppleNewsURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        guard let host = URL(string: String(first))?.host?.lowercased() else { return false }
        return host == "apple.news" || host.hasSuffix(".apple.news")
    }

    /// Returns the first non-empty text payload found across the providers.
    public static func loadSharedText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = await loadText(from: provider), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// Parse + enqueue shared text. Returns the status to display.
    public static func importSharedText(_ text: String) -> ShareImportStatus {
        if isAppleNewsURL(text) {
            return .failure(message: "Apple News only shares a link — your score isn't included.\n\nOpen Puzzle House, tap +, and choose \u{201C}Log Emoji Game\u{201D} to enter your moves. It takes one tap.")
        }
        guard let parsed = ParserRegistry.parse(text) else {
            return .failure(message: "We don't recognize this puzzle format yet.")
        }
        guard let container = AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup) else {
            return .failure(message: "Couldn't access shared storage. Open the app and try again.")
        }
        let queue = OfflineWriteQueue(container: container)
        let placeholder = PuzzleResult(
            householdID: "pending",
            authorUserID: "pending",
            gameID: parsed.gameID,
            puzzleNumber: parsed.puzzleNumber,
            puzzleDay: PuzzleDay(date: Date(), timeZone: .current),
            rawScore: parsed.rawScore,
            rawPayload: text,
            gridData: parsed.gridData
        )
        do {
            try queue.enqueue(placeholder)
            let game = ParserRegistry.displayName(for: parsed.gameID) ?? parsed.gameID
            return .success(
                message: "Saved \(game) #\(parsed.puzzleNumber). Open Puzzle House to see the leaderboard."
            )
        } catch {
            return .failure(message: "Couldn't save: \(error.localizedDescription)")
        }
    }

    // MARK: Provider loading

    /// Tries a battery of text-shaped type identifiers and returns the first
    /// non-empty string it can coax out of the provider.
    static func loadText(from provider: NSItemProvider) async -> String? {
        let preferred: [UTType] = [.plainText, .utf8PlainText, .text, .url]
        for type in preferred {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            if let s = await loadString(provider, typeIdentifier: type.identifier) {
                return s
            }
        }
        for id in provider.registeredTypeIdentifiers
        where id.contains("text") || id.contains("plain") {
            if let s = await loadString(provider, typeIdentifier: id) {
                return s
            }
        }
        return nil
    }

    private static func loadString(_ provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let s = item as? String {
                    continuation.resume(returning: s)
                } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: s)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
