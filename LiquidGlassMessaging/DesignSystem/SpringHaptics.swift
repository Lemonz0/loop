import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Thread-safe, non-isolated haptic feedback coordinator tailored for iOS micro-interactions.
/// Can be invoked synchronously from any context (background tasks, view bodies, actor methods).
public enum HapticFeedback: Sendable {
    
    public static func soft() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred()
        }
        #endif
    }
    
    public static func rigid() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred()
        }
        #endif
    }
    
    public static func light() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        }
        #endif
    }
    
    public static func medium() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        }
        #endif
    }
    
    public static func selection() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
        #endif
    }
    
    public static func success() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
        #endif
    }
    
    public static func error() {
        #if canImport(UIKit)
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        #endif
    }
}

public struct LiquidGlassButtonStyle: ButtonStyle {
    public var scaleOnPress: CGFloat = 0.94
    
    public init(scaleOnPress: CGFloat = 0.94) {
        self.scaleOnPress = scaleOnPress
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleOnPress : 1.0)
            .animation(GlassTheme.snappySpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticFeedback.soft()
                }
            }
    }
}

public extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlassInteractive: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }
    
    static func liquidGlassInteractive(scale: CGFloat) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(scaleOnPress: scale)
    }
}
