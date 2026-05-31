import SwiftUI
import PuzzleCore
import PuzzleParsers
import PuzzleScoring
import PuzzleUI

public struct TodayView: View {
    @Bindable var store: HouseholdStore
    @State private var showingPaste = false
    @State private var openResult: PuzzleResult?
    @State private var openMember: String?
    @State private var showingSwitcher = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: HouseholdStore) {
        self.store = store
    }

    public var body: some View {
        scrollBody
            .background(PuzzleBackground().ignoresSafeArea())
            .sheet(item: $openResult) { result in
                ResultDetailSheet(store: store, result: result)
            }
            .sheet(item: memberBinding) { picked in
                MemberDetailSheet(store: store, userID: picked.id)
            }
            .sheet(isPresented: $showingSwitcher) {
                HouseSwitcherView(store: store)
            }
            .refreshable { await store.refresh() }
            // iOS shows its own "Add" toolbar button + paste sheet here; on
            // macOS the window toolbar owns Add Result, so this is a no-op.
            .todayAddResult(isPresented: $showingPaste, store: store)
            .paneNavigation(title: "Today")
    }

    private var scrollBody: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ChecklistSection(store: store) { openMember = $0 }
                    leaderboard
                    resultCards
                }
            }
            .padding()
            .macReadableWidth()
        }
    }

    private var memberBinding: Binding<MemberID?> {
        Binding(
            get: { openMember.map(MemberID.init) },
            set: { openMember = $0?.id }
        )
    }

    private struct MemberID: Identifiable { let id: String }

    private var header: some View {
        HStack(alignment: .top) {
            Button {
                showingSwitcher = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let household = store.selectedHousehold {
                        HStack(spacing: 6) {
                            Text("\(household.iconEmoji) \(household.name)")
                                .font(.title2).bold()
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(store.today.isoString)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
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
                    Button {
                        openMember = score.userID
                    } label: {
                        leaderboardRow(idx: idx, score: score)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .puzzleCard()
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
                size: 32,
                photoData: store.avatarPhotoData(for: score.userID)
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
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (idx == 0 ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12)),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        idx == 0 ? Color.accentColor.opacity(0.45) : Color.clear,
                        lineWidth: 0.5
                    )
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
                            hideGrid: (visibility[result.id] ?? .full) == .hidden,
                            reactionSummary: store.reactionSummary(for: result.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .puzzleTransition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity
                    ), reduceMotion: reduceMotion)
                }
            }
        }
        .puzzleAnimation(
            .spring(response: 0.4, dampingFraction: 0.85),
            value: store.todayResults.map(\.id),
            reduceMotion: reduceMotion
        )
    }

    private var emptyResults: some View {
        PuzzleEmptyState(
            symbol: "puzzlepiece",
            title: "No results yet",
            message: "Tap + to paste or share a puzzle."
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PuzzleTheme.cardCornerRadius))
    }
}

private extension View {
    /// iOS-only "Add" toolbar button + paste sheet for `TodayView`. On macOS the
    /// window toolbar (`RootMacView`) owns Add Result, so this passes through
    /// unchanged — preventing a duplicate add button.
    @ViewBuilder
    func todayAddResult(isPresented: Binding<Bool>, store: HouseholdStore) -> some View {
        #if os(iOS)
        self
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresented.wrappedValue = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: isPresented) {
                PasteSubmitView { parsed, raw in
                    try await store.submit(parsed: parsed, rawPayload: raw)
                }
            }
        #else
        self
        #endif
    }
}
