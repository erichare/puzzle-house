import SwiftUI
import PuzzleCore
import PuzzleUI

public struct PuzzleHouseRootView: View {
    @Bindable var store: HouseholdStore
    @State private var didPromptProfile = false
    @State private var showOnboarding = !ProfileDefaults.hasOnboarded

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView("Loading your houses\u{2026}")
            case .error(let message):
                PuzzleEmptyState(
                    symbol: "exclamationmark.icloud",
                    title: "Couldn't load",
                    message: message
                )
            case .ready:
                content
            }
        }
        .task {
            if store.state == .idle { await store.bootstrap() }
            // Cold-launch invite: the scene stashed the metadata before we were
            // ready; now that we're bootstrapped, accept it.
            await store.drainPendingShareIfNeeded()
        }
        .overlay {
            if store.isJoining { JoiningOverlay() }
        }
        .overlay {
            if let celebration = store.pendingCelebration {
                CelebrationOverlay(celebration: celebration) {
                    store.consumeCelebration()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.snappy, value: store.isJoining)
        .animation(.snappy, value: store.pendingCelebration)
        // One-time prompt to pick a name + avatar so we don't show "Me" /
        // "New member" to the rest of the house. Suppressed while the richer
        // onboarding flow is up so we don't stack modals.
        .sheet(isPresented: Binding(
            get: { store.needsProfileSetup && !didPromptProfile && !showOnboarding },
            set: { presenting in if !presenting { didPromptProfile = true } }
        )) {
            EditMyMembershipSheet(store: store)
        }
        .onboardingCover(isPresented: $showOnboarding, store: store)
    }

    private var content: some View {
        PuzzleHouseAdaptiveRoot(store: store)
    }
}

/// Shown while we're accepting an invite and waiting for the shared house to
/// replicate, so tapping a link gives immediate feedback instead of a blank
/// beat before the house appears.
private struct JoiningOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Joining house\u{2026}").font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity)
    }
}

private extension View {
    /// Presents onboarding as a full-screen cover on iOS and a sheet on macOS
    /// (macOS has no `fullScreenCover`).
    @ViewBuilder
    func onboardingCover(isPresented: Binding<Bool>, store: HouseholdStore) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented) {
            OnboardingFlow(store: store) { isPresented.wrappedValue = false }
        }
        #else
        self.sheet(isPresented: isPresented) {
            OnboardingFlow(store: store) { isPresented.wrappedValue = false }
                .frame(minWidth: 520, minHeight: 600)
        }
        #endif
    }
}
