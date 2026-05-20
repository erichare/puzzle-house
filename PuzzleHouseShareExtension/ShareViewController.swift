import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PuzzleCore
import PuzzleParsers
import PuzzleCloudKit

/// Share Extension entry point. Hosts a SwiftUI status view so the user
/// always sees feedback — loading → success or failure → Done. Tapping Done
/// calls `completeRequest`.
public final class ShareViewController: UIViewController {

    enum Status: Equatable {
        case loading
        case success(message: String)
        case failure(message: String)
    }

    private let model = ShareStatusModel()
    private var hostingController: UIHostingController<ShareStatusView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installHostingController()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if model.status == .loading {
            Task { await processInput() }
        }
    }

    private func installHostingController() {
        let view = ShareStatusView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    @MainActor
    private func processInput() async {
        guard let context = extensionContext,
              let items = context.inputItems as? [NSExtensionItem]
        else {
            model.status = .failure(message: "Nothing to import.")
            return
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if let text = await ShareViewController.loadText(from: provider), !text.isEmpty {
                    if ShareViewController.isAppleNewsURL(text) {
                        model.status = .failure(message: "Apple News only shares a link — your score isn't included.\n\nTake a screenshot of the puzzle and tap + in Puzzle House, then \u{201C}Pick from Photos\u{201D}.")
                        return
                    }
                    await handle(text: text)
                    return
                }
            }
        }
        model.status = .failure(message: "We couldn't read the shared text. Try copy/paste in the app.")
    }

    static func isAppleNewsURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Either a bare apple.news URL, or a longer payload starting with one.
        guard let first = trimmed.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        let s = String(first)
        guard let host = URL(string: s)?.host?.lowercased() else { return false }
        return host == "apple.news" || host.hasSuffix(".apple.news")
    }

    @MainActor
    private func handle(text: String) async {
        guard let parsed = ParserRegistry.parse(text) else {
            model.status = .failure(message: "We don't recognize this puzzle format yet.")
            return
        }
        guard let container = AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup) else {
            model.status = .failure(message: "Couldn't access shared storage. Open the app and try again.")
            return
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
            model.status = .success(
                message: "Saved \(game) #\(parsed.puzzleNumber). Open Puzzle House to see the leaderboard."
            )
        } catch {
            model.status = .failure(message: "Couldn't save: \(error.localizedDescription)")
        }
    }

    /// Tries a battery of text-shaped type identifiers and returns the first
    /// non-empty string it can coax out of the provider.
    private static func loadText(from provider: NSItemProvider) async -> String? {
        let preferred: [UTType] = [
            .plainText, .utf8PlainText, .text, .url,
        ]
        for type in preferred {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            if let s = await loadString(provider, typeIdentifier: type.identifier) {
                return s
            }
        }
        // Last-ditch attempt: any registered identifier whose name hints at text.
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

// MARK: - SwiftUI status view

@MainActor
@Observable
final class ShareStatusModel {
    var status: ShareViewController.Status = .loading
}

struct ShareStatusView: View {
    @Bindable var model: ShareStatusModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            iconAndTitle
            messageText
            Spacer()
            if case .loading = model.status {
                EmptyView()
            } else {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var iconAndTitle: some View {
        switch model.status {
        case .loading:
            ProgressView().controlSize(.large)
            Text("Reading puzzle\u{2026}").font(.headline)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .resizable().frame(width: 64, height: 64)
                .foregroundStyle(.green)
            Text("Saved to Puzzle House").font(.headline)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable().frame(width: 64, height: 64)
                .foregroundStyle(.orange)
            Text("Couldn't import").font(.headline)
        }
    }

    @ViewBuilder
    private var messageText: some View {
        switch model.status {
        case .loading:
            EmptyView()
        case .success(let m), .failure(let m):
            Text(m)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }
}
