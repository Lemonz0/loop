import SwiftUI

extension View {
    /// Shared native slab presentation for profiles and posts.
    func floatingGlassSheet(selection: Binding<PresentationDetent>? = nil) -> some View {
        modifier(FloatingGlassSheetModifier(selection: selection))
    }
}
private struct FloatingGlassSheetModifier: ViewModifier {
    let selection: Binding<PresentationDetent>?
    @State private var defaultDetent: PresentationDetent = .medium
    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: selection ?? $defaultDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
            .background { ProfileBackdropDismiss().frame(width: 0, height: 0).allowsHitTesting(false) }
    }
}
