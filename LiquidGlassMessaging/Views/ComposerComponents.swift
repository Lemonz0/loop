import SwiftUI

enum ComposerLayout {
    static let barHeight: CGFloat = 50
    static let fieldHeight: CGFloat = 36
    static let leadingInset: CGFloat = 4
    static let spacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 3
}
struct ComposerCapsule<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content
    var body: some View {
        let glass = reduceTransparency || contrast == .increased ? Glass.regular.tint(theme.backgroundBase) : Glass.regular
        HStack(alignment: .center, spacing: ComposerLayout.spacing) { content }
            .padding(.horizontal, ComposerLayout.horizontalPadding).padding(.vertical, ComposerLayout.verticalPadding)
            .glassEffect(glass.interactive(), in: Capsule())
    }
}
/// One stable button lets SF Symbols replace the microphone with the send arrow.
struct ComposerActionButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var symbol = "arrow.up"
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .frame(width: 34, height: 28)
        }.buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.small)
            .frame(width: 50, height: 44).contentShape(Rectangle()).offset(x: -4)
            .tint(theme.accent).accessibilityLabel(label)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: symbol)
    }
}

private struct ComposerPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recording = false
    var body: some View {
        ZStack {
            AmbientGlowBackground()
            GlassEffectContainer(spacing: 8) {
                ComposerCapsule {
                    Text(recording ? "Recording 0:12" : "Message").font(.body).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: ComposerLayout.fieldHeight, alignment: .leading)
                        .padding(.leading, ComposerLayout.leadingInset)
                    ComposerActionButton(symbol: recording ? "arrow.up" : "mic.fill", label: recording ? "Send voice message" : "Record voice message") { recording.toggle() }
                }
            }.padding(20)
        }.animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: recording)
    }
}
#Preview("Shared composer · dark") { ComposerPreview().circlePreviewTheme(.aurora) }
#Preview("Shared composer · light") { ComposerPreview().circlePreviewTheme(.daylight) }
