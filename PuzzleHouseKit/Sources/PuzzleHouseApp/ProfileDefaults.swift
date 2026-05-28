import Foundation
import PuzzleCloudKit

/// Device-local memory of the name and avatar emoji the user picked for
/// themselves, used to seed new household memberships so they only type their
/// name once. The per-household `Membership` records (synced via CloudKit)
/// stay the source of truth for what other members actually see — this is just
/// a convenience default.
enum ProfileDefaults {
    private static let nameKey = "puzzle-house.profile.displayName"
    private static let emojiKey = "puzzle-house.profile.avatarEmoji"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PuzzleHouseIdentifiers.appGroup) ?? .standard
    }

    /// The user's chosen name, or nil if they haven't set one yet.
    static var displayName: String? {
        get {
            let value = defaults.string(forKey: nameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set { defaults.set(newValue, forKey: nameKey) }
    }

    static var avatarEmoji: String? {
        get { defaults.string(forKey: emojiKey) }
        set { defaults.set(newValue, forKey: emojiKey) }
    }
}
