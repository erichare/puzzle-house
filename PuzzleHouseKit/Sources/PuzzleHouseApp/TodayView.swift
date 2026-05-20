import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleScoring
import PuzzleUI

public struct TodayView: View {
    @Bindable var store: HouseholdStore
    @State private var showingPaste = false
    @State private var openResult: PuzzleResult?

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    leaderboard
                    resultCards
                }
                .padding()
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingPaste = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPaste) {
                PasteSubmitView { parsed, raw in
                    try await store.submit(parsed: parsed, rawPayload: raw)
                }
            }
            .sheet(item: $openResult) { result in
                ResultDetailSheet(store: store, result: result)
            }
            .refreshable { await store.refresh() }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.97, blue: 0.93),
                Color(red: 1.00, green: 0.93, blue: 0.86),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let household = store.selectedHousehold {
                    Text("\(household.iconEmoji) \(household.name)")
                        .font(.title2).bold()
                }
                Text(store.today.isoString)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.houseStreak > 0 {
                StreakBadge(count: store.houseStreak, label: "house streak")
            }
        }
    }

    @ViewBuilder
    private var leaderboard: some View {
        let board = store.leaderboard
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's household")
                .font(.headline)
            if board.isEmpty {
                emptyLeaderboard
            } else {
                ForEach(Array(board.enumerated()), id: \.element.userID) { idx, score in
                    leaderboardRow(idx: idx, score: score)
                }
            }
        }
        .padding(PuzzleTheme.cardPadding)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var emptyLeaderboard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No results yet. Be first.")
                .foregroundStyle(.secondary).font(.callout)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func leaderboardRow(idx: Int, score: PlayerDailyScore) -> some View {
        HStack(spacing: 12) {
            Text("\(idx + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(idx == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            Avatar(
                emoji: store.avatarEmoji(for: score.userID),
                displayName: store.displayName(for: score.userID),
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(for: score.userID)).font(.body)
                if let topGame = score.perGame.keys.first {
                    let s = store.gameStreak(userID: score.userID, gameID: topGame)
                    if s > 0 {
                        Text("🔥 \(s) \(ParserRegistry.displayName(for: topGame) ?? topGame)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(String(format: "%+.2f", score.combined))
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(idx == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (idx == 0 ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10)),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private var resultCards: some View {
        let visibility = store.spoilerMap
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.headline)
                Spacer()
                if store.todayResults.isEmpty == false {
                    Text("\(store.todayResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.todayResults.isEmpty {
                emptyResults
            } else {
                ForEach(store.todayResults) { result in
                    let game = Game.known(by: result.gameID)
                    Button {
                        openResult = result
                    } label: {
                        ResultCard(
                            result: result,
                            authorName: store.displayName(for: result.authorUserID),
                            authorEmoji: store.avatarEmoji(for: result.authorUserID),
                            gameDisplayName: game?.displayName ?? result.gameID,
                            gameEmoji: game?.emoji ?? "🧩",
                            accentColor: game?.color ?? .accentColor,
                            hideGrid: (visibility[result.id] ?? .full) == .hidden
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No results yet")
                .font(.headline)
            Text("Tap + to paste or share a puzzle.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
    }
}
