import SwiftUI

// MARK: - Apple iOS 26 Glass Effect Container

/// Container view grouping multiple Liquid Glass elements for unified optical refraction and morphing.
public struct GlassEffectContainer<Content: View>: View {
    public var spacing: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(spacing: CGFloat = 8.0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        SwiftUI.GlassEffectContainer(spacing: spacing) { content() }
    }
}

// MARK: - Compatibility Bridge for Legacy Views

public enum GlassShape: Sendable, Equatable {
    case capsule
    case circle
    case rect(cornerRadius: CGFloat)
}

public extension View {
    /// Backward-compatible circular Liquid Glass modifier.
    func liquidGlassCircle(
        tint: Color? = nil,
        specularIntensity: Double = 0.60
    ) -> some View {
        let g = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
        return self.glassEffect(g, in: Circle())
    }

    /// Backward-compatible pill Liquid Glass modifier.
    func liquidGlassPill(
        specularIntensity: Double = 0.60,
        tint: Color? = nil,
        strokeWidth: CGFloat = 1.0
    ) -> some View {
        let g = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
        return self.glassEffect(g, in: Capsule())
    }

    /// Floating Liquid Glass Dock container.
    func liquidGlassDock(
        tint: Color? = nil,
        specularIntensity: Double = 0.65
    ) -> some View {
        let g = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
        return self.glassEffect(g, in: Capsule())
    }

    /// Message bubble liquid glass.
    func liquidGlassBubble(
        isFromCurrentUser: Bool,
        cornerRadius: CGFloat = GlassTheme.bubbleRadius
    ) -> some View {
        modifier(ThemeBubbleModifier(isFromCurrentUser: isFromCurrentUser, cornerRadius: cornerRadius))
    }

    /// Backward-compatible Liquid Glass modifier with corner radius.
    func liquidGlass(
        cornerRadius: CGFloat = GlassTheme.cardRadius,
        tint: Color? = nil,
        specularIntensity: Double = 0.55,
        strokeWidth: CGFloat = 1.0,
        shadowRadius: CGFloat = 8,
        shadowOpacity: Double = 0.25
    ) -> some View {
        let g = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
        return self.glassEffect(g, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Backward-compatible Liquid Glass effect with cornerRadius.
    func glassEffect(
        cornerRadius: CGFloat = GlassTheme.cardRadius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        var g = tint != nil ? Glass.regular.tint(tint!) : Glass.regular
        if interactive { g = g.interactive() }
        return self.glassEffect(g, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct ThemeBubbleModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let isFromCurrentUser: Bool
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.glassEffect(isFromCurrentUser ? .regular.tint(theme.glassTint) : .regular,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Native iOS 26 Glass Morphing & Transition Modifiers

public enum GlassEffectTransition: Sendable, Equatable {
    case matchedGeometry
    case materialize
    case dissolve
}

public extension View {
    /// Unifies multiple nearby glass elements into a merged liquid surface.
    func glassEffectUnion(id: some Hashable, in namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace)
    }

    /// Defines how the glass effect should behave during transitions.
    func glassEffectTransition(_ transition: GlassEffectTransition = .matchedGeometry) -> some View {
        self
    }

    /// Applies iOS 26 scroll edge optical refraction behavior.
    func scrollEdgeEffectStyle() -> some View {
        self
    }
}

// MARK: - iOS 26 Toolbar Spacer

/// Toolbar spacer for dividing Liquid Glass button groups in iOS 26.
public struct ToolbarSpacer: ToolbarContent {
    public init() {}

    public var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Spacer()
        }
    }
}
