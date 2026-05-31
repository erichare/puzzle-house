#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback. Replaces scattered raw `UI*FeedbackGenerator`
/// calls with named intents, and no-ops on platforms without UIKit (macOS).
public enum Haptics {
    /// A successful, completed action (result submitted, milestone hit).
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Something that didn't go through cleanly (failed parse, validation).
    public static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// A light tap for incidental interactions (reaction tap, toggle).
    public static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Discrete selection change (picker / segmented movement).
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// A celebratory success, prepared first for low latency. Use for the
    /// milestone/streak-save celebration moment.
    @MainActor
    public static func celebrate() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}
