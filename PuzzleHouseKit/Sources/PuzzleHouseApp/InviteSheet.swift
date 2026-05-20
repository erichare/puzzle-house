import SwiftUI
import PuzzleCore
import PuzzleUI
import PuzzleCloudKit
#if canImport(UIKit)
import UIKit
#endif

/// Presents Apple's native CloudKit sharing sheet
/// (`UICloudSharingController`) for inviting people to a household. iCloud
/// expects shares to be created through this controller — the previous
/// approach of generating a bare `share.url` via `ShareLink` produced URLs
/// that iCloud sometimes refused to accept ("Item Unavailable / The owner
/// stopped sharing or your account doesn't have permission").
public struct InviteSheet: View {
    let store: HouseholdStore
    let household: Household
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(store: HouseholdStore, household: Household) {
        self.store = store
        self.household = household
    }

    public var body: some View {
        #if canImport(UIKit)
        ZStack {
            CloudSharingControllerView(
                household: household,
                onSave: { dismiss() },
                onStop: { dismiss() },
                onError: { error in
                    errorMessage = "\(error)"
                }
            )
            .ignoresSafeArea()
            if let errorMessage {
                errorOverlay(message: errorMessage)
            }
        }
        #else
        macOSFallback
        #endif
    }

    private func errorOverlay(message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text("Couldn't open share").font(.headline)
                Text(message)
                    .font(.caption).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
            Spacer()
        }
        .background(Color.black.opacity(0.4).ignoresSafeArea())
    }

    private var macOSFallback: some View {
        VStack(spacing: 16) {
            Text("CloudKit sharing is only available on iOS / iPadOS.")
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.glassProminent)
        }
        .padding(40)
    }
}
