import SwiftUI

extension View {
    /// The Today / Stats / History feature views are standalone tabs on iOS and
    /// supply their own `NavigationStack` + title. On macOS they're embedded in
    /// `RootMacView`'s `NavigationSplitView` detail, which already owns the
    /// navigation chrome (title bar + toolbar), so we render the bare content to
    /// avoid a doubled title bar and a duplicate toolbar.
    @ViewBuilder
    func paneNavigation(title: String) -> some View {
        #if os(macOS)
        self
        #else
        NavigationStack { self.navigationTitle(title) }
        #endif
    }

    /// On macOS, constrain content to a comfortable reading width and center it —
    /// content-dense card layouts look awkward stretched across a wide window.
    /// No-op on iOS, where the content already fits the device width.
    @ViewBuilder
    func macReadableWidth(_ maxWidth: CGFloat = 760) -> some View {
        #if os(macOS)
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}
