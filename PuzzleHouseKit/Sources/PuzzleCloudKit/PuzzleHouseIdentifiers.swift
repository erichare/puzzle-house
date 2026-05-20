import Foundation

/// Single source of truth for identifiers that must match between Swift code
/// and entitlement plists. If you change one of these, also update:
/// - PuzzleHouse/PuzzleHouse.entitlements
/// - PuzzleHouseShareExtension/PuzzleHouseShareExtension.entitlements
/// - PuzzleHouseMessages/PuzzleHouseMessages.entitlements
/// - project.yml (PRODUCT_BUNDLE_IDENTIFIER lines)
public enum PuzzleHouseIdentifiers {
    /// CloudKit container identifier shared by all targets.
    public static let iCloudContainer = "iCloud.com.jestats.PuzzleHouse"

    /// App Group container identifier — shared filesystem for the offline
    /// write queue and change-token store.
    public static let appGroup = "group.com.jestats.PuzzleHouse"

    /// Top-level bundle ID prefix.
    public static let bundleIDPrefix = "com.jestats.PuzzleHouse"
}
