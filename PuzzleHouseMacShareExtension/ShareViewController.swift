import AppKit
import SwiftUI
import PuzzleShareKit

/// macOS Share Extension shell. Hosts the shared `ShareStatusView` via
/// `NSHostingView` and runs the shared `ShareImportCore`, so behavior is
/// identical to the iOS extension. Reads the shared item providers, parses, and
/// enqueues into the app-group offline queue; the main app drains it on launch.
final class ShareViewController: NSViewController {

    private let model = ShareStatusModel()

    override func loadView() {
        let host = NSHostingView(
            rootView: ShareStatusView(model: model) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        host.setFrameSize(NSSize(width: 360, height: 300))
        view = host
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if model.status == .loading {
            Task { await processInput() }
        }
    }

    @MainActor
    private func processInput() async {
        guard let context = extensionContext,
              let items = context.inputItems as? [NSExtensionItem]
        else {
            model.status = .failure(message: "Nothing to import.")
            return
        }
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let text = await ShareImportCore.loadSharedText(from: providers), !text.isEmpty else {
            model.status = .failure(message: "We couldn't read the shared text. Try copy/paste in the app.")
            return
        }
        model.status = ShareImportCore.importSharedText(text)
    }
}
