import SwiftUI

/// Observable status backing `ShareStatusView`, shared by the iOS and macOS
/// Share extensions.
@MainActor
@Observable
public final class ShareStatusModel {
    public var status: ShareImportStatus = .loading
    public init() {}
}

/// The share-extension UI: a loading → success/failure status with a Done
/// button. Pure SwiftUI, so it hosts in `UIHostingController` (iOS) or
/// `NSHostingView` (macOS) unchanged.
public struct ShareStatusView: View {
    @Bindable var model: ShareStatusModel
    let onDismiss: () -> Void

    public init(model: ShareStatusModel, onDismiss: @escaping () -> Void) {
        self.model = model
        self.onDismiss = onDismiss
    }

    public var body: some View {
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
        .frame(minWidth: 320, minHeight: 260)
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
        case .success(let message), .failure(let message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }
}
