import UIKit
import SwiftUI
import PuzzleShareKit

/// iOS Share Extension shell. Hosts the shared `ShareStatusView` and runs the
/// shared `ShareImportCore`; all parsing/enqueue logic lives in `PuzzleShareKit`
/// so iOS and macOS stay identical.
public final class ShareViewController: UIViewController {

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
        let statusView = ShareStatusView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: statusView)
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
