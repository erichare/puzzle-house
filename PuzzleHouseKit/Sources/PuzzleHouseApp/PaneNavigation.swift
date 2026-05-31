import SwiftUI

extension View {
    /// The Today / Stats / History feature views are standalone tabs on a
    /// compact iPhone and supply their own `NavigationStack` + title. On macOS,
    /// and on a regular-width iPad where they're embedded in a
    /// `NavigationSplitView` detail, the host already owns the navigation chrome,
    /// so we render the bare content to avoid a doubled title bar.
    @ViewBuilder
    func paneNavigation(title: String) -> some View {
        #if os(macOS)
        self
        #else
        AdaptivePane(title: title) { self }
        #endif
    }

    /// On macOS / regular-width iPad, constrain content to a comfortable reading
    /// width and center it — content-dense card layouts look awkward stretched
    /// across a wide window. No-op on a compact iPhone.
    @ViewBuilder
    func macReadableWidth(_ maxWidth: CGFloat = 760) -> some View {
        #if os(macOS)
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        #else
        ReadableWidth(maxWidth: maxWidth) { self }
        #endif
    }
}

#if os(iOS)
/// Wraps a feature view in a `NavigationStack` only when compact (iPhone / iPad
/// slide-over). In regular width the embedding `NavigationSplitView` owns the
/// chrome, so we pass the bare content through.
private struct AdaptivePane<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            content()
        } else {
            NavigationStack { content().navigationTitle(title) }
        }
    }
}

/// Centers and width-limits content in regular width (iPad), no-op when compact.
private struct ReadableWidth<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            content().frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        } else {
            content()
        }
    }
}
#endif
