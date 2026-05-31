import SwiftUI
import PuzzleScoring

/// A grid of `TrophyBadge`s grouped by category, with an earned/total count.
/// Takes plain engine output so it has no `HouseholdStore` dependency (consistent
/// with `ResultCard` taking values rather than the store).
public struct TrophyShelfView: View {
    public typealias Item = (definition: AchievementDefinition, earned: Bool, progress: AchievementProgress?)
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    public var body: some View {
        let earnedCount = items.filter(\.earned).count
        VStack(alignment: .leading, spacing: PuzzleSpacing.m) {
            HStack {
                Text("Trophies").font(PuzzleFont.sectionHeader)
                Spacer()
                Text("\(earnedCount)/\(items.count)")
                    .font(PuzzleFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(AchievementCategory.allCases, id: \.self) { category in
                let group = items.filter { $0.definition.category == category }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: PuzzleSpacing.s) {
                        Text(title(for: category))
                            .font(PuzzleFont.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group, id: \.definition.id) { item in
                                TrophyBadge(definition: item.definition, earned: item.earned, progress: item.progress)
                            }
                        }
                    }
                }
            }
        }
    }

    private func title(for category: AchievementCategory) -> String {
        switch category {
        case .streak: return "Streaks"
        case .perfect: return "Perfect play"
        case .breadth: return "Breadth"
        case .social: return "Social"
        case .volume: return "Volume"
        }
    }
}
