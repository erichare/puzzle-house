import SwiftUI

/// Gates animation on the Reduce Motion accessibility setting. State still
/// updates when motion is reduced — only the *animation* is dropped — so the
/// UI stays correct while respecting the user's preference.
///
/// Read the flag from the environment, then route motion through the gate:
/// ```
/// @Environment(\.accessibilityReduceMotion) private var reduceMotion
/// ...
/// ReduceMotionGate(reduceMotion).animate(.spring) { expanded.toggle() }
/// ```
public struct ReduceMotionGate: Sendable {
    public let reduceMotion: Bool

    public init(_ reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    /// The animation to use, or `nil` (no animation) under Reduce Motion.
    public func resolved(_ animation: Animation?) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Run a state mutation with the given animation, suppressed under Reduce Motion.
    @MainActor
    public func animate<Result>(
        _ animation: Animation? = .default,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(resolved(animation), body)
    }
}

public extension View {
    /// Animate on `value` changes, automatically dropped under Reduce Motion.
    func puzzleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V,
        reduceMotion: Bool
    ) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }

    /// Apply a transition that collapses to a plain `.opacity` under Reduce Motion.
    func puzzleTransition(_ transition: AnyTransition, reduceMotion: Bool) -> some View {
        self.transition(reduceMotion ? .opacity : transition)
    }
}
