import UIKit
import Messages
import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleCloudKit
import PuzzleHouseApp

/// iMessage app entry point. Hosts a SwiftUI picker of today's results; tapping
/// a row inserts an `MSMessage` into the active conversation so the user can
/// tap Send.
public final class MessagesViewController: MSMessagesAppViewController {

    private var hostingController: UIHostingController<MessagesRootView>?
    private var store: HouseholdStore?

    public override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        installHostingControllerIfNeeded()
    }

    private func installHostingControllerIfNeeded() {
        guard hostingController == nil else { return }

        let store = makeStore()
        self.store = store
        let root = MessagesRootView(store: store) { [weak self] result in
            self?.send(result)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    private func makeStore() -> HouseholdStore {
        let appGroup = AppGroupContainer(appGroupIdentifier: PuzzleHouseIdentifiers.appGroup)
        let queue = appGroup.map { OfflineWriteQueue(container: $0) }
        let service = CloudKitService(writeQueue: queue)
        return HouseholdStore(service: service, queue: queue)
    }

    // MARK: - Sending

    private func send(_ result: PuzzleResult) {
        guard let conversation = activeConversation else { return }
        let message = Self.buildMessage(for: result, in: store)
        conversation.insert(message) { _ in }
        requestPresentationStyle(.compact)
    }

    static func buildMessage(for result: PuzzleResult, in store: HouseholdStore?) -> MSMessage {
        let game = Game.known(by: result.gameID)
        let gameName = game?.displayName ?? result.gameID
        let summary = MessagesPickerView.summary(for: result)
        let authorName = store?.displayName(for: result.authorUserID) ?? "Someone"

        let layout = MSMessageTemplateLayout()
        layout.caption = "\(authorName) — \(gameName) #\(result.puzzleNumber)"
        layout.subcaption = summary
        layout.trailingSubcaption = game?.emoji

        let session = MSSession()
        let message = MSMessage(session: session)
        message.layout = layout
        message.summaryText = "\(gameName) #\(result.puzzleNumber) — \(summary)"
        if var components = URLComponents(string: "https://puzzlehouse.app/result") {
            components.queryItems = [
                URLQueryItem(name: "id", value: result.id),
                URLQueryItem(name: "game", value: result.gameID),
                URLQueryItem(name: "puzzle", value: String(result.puzzleNumber)),
            ]
            message.url = components.url
        }
        return message
    }
}

private struct MessagesRootView: View {
    @Bindable var store: HouseholdStore
    let onSend: @MainActor (PuzzleResult) -> Void

    var body: some View {
        MessagesPickerView(store: store, onSend: onSend)
    }
}
