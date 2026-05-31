import SwiftUI
import PuzzleCore
import PuzzleUI

/// Lightweight first-run flow: welcome → name/avatar → create/join a house →
/// notifications. Reuses the store's existing mutations and writes the profile
/// to `ProfileDefaults`, which propagates to the membership on next load.
struct OnboardingFlow: View {
    @Bindable var store: HouseholdStore
    let onFinish: () -> Void

    @State private var step = 0
    @State private var name = ProfileDefaults.displayName ?? ""
    @State private var emoji = ProfileDefaults.avatarEmoji ?? "🧩"
    @State private var newHouseName = ""
    @State private var working = false

    private let avatarChoices = ["🧩", "😀", "😎", "🦊", "🐼", "🐯", "🦄", "🌟", "🔥", "🎯", "🧠", "🐙"]
    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PuzzleSpacing.xl) {
                    stepContent
                }
                .padding(PuzzleSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            controls
        }
        .background(PuzzleBackground().ignoresSafeArea())
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcome
        case 1: profileStep
        case 2: houseStep
        default: readyStep
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: PuzzleSpacing.l) {
            Text("Welcome to\nPuzzle House").font(.largeTitle.bold())
            Text("Track your family's daily puzzles — Wordle, Connections, Strands and the Emoji Game — on one shared leaderboard.")
                .font(.title3).foregroundStyle(.secondary)
            HStack(spacing: PuzzleSpacing.m) {
                ForEach(Game.known, id: \.id) { Text($0.emoji).font(.system(size: 40)) }
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: PuzzleSpacing.l) {
            Text("Who are you?").font(.title.bold())
            Text("This is how your family sees you.").foregroundStyle(.secondary)
            HStack(spacing: PuzzleSpacing.m) {
                Text(emoji).font(.system(size: 52))
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 10) {
                ForEach(avatarChoices, id: \.self) { choice in
                    Button { emoji = choice } label: {
                        Text(choice).font(.system(size: 34)).frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .background(
                        emoji == choice ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1),
                        in: Circle()
                    )
                }
            }
        }
    }

    private var houseStep: some View {
        VStack(alignment: .leading, spacing: PuzzleSpacing.l) {
            Text("Your house").font(.title.bold())
            if let h = store.selectedHousehold {
                Text("You're in \(h.iconEmoji) \(h.name).").font(.title3)
                Text("Invite family or create another house anytime from the Houses tab.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Create a house for your family, or ask someone to send you an invite link.")
                    .foregroundStyle(.secondary)
                TextField("House name (e.g. The Smiths)", text: $newHouseName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Button {
                    createHouse()
                } label: {
                    if working {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Create house").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(newHouseName.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: PuzzleSpacing.l) {
            Text("You're all set!").font(.title.bold())
            Text("Paste or share a puzzle result to get on the board. Want a nudge when family plays?")
                .foregroundStyle(.secondary)
            Button("Turn on notifications") {
                Task { await store.requestNotificationPermission() }
            }
            .buttonStyle(.glass)
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(.glass)
            }
            Spacer()
            Button(step == totalSteps - 1 ? "Start playing" : "Continue") { advance() }
                .buttonStyle(.glassProminent)
        }
        .padding(PuzzleSpacing.l)
    }

    private func advance() {
        if step == 1 {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { ProfileDefaults.displayName = trimmed }
            ProfileDefaults.avatarEmoji = emoji
        }
        if step == totalSteps - 1 {
            ProfileDefaults.hasOnboarded = true
            onFinish()
        } else {
            withAnimation { step += 1 }
        }
    }

    private func createHouse() {
        let trimmed = newHouseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        working = true
        Task {
            try? await store.createHousehold(name: trimmed, iconEmoji: emoji)
            working = false
            withAnimation { step += 1 }
        }
    }
}
