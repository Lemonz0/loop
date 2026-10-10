import SwiftUI

/// Design tokens, gradients, and specular lighting parameters for the Liquid Glass aesthetic.
public enum GlassTheme {
    // MARK: - Corner Radii
    public static let pillRadius: CGFloat = 999
    public static let cardRadius: CGFloat = 26
    public static let bubbleRadius: CGFloat = 20
    public static let smallRadius: CGFloat = 12

    // MARK: - Animation Springs
    public static let fluidSpring = Animation.spring(response: 0.38, dampingFraction: 0.78, blendDuration: 0)
    public static let snappySpring = Animation.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0)
    public static let sheetSpring = Animation.spring(response: 0.45, dampingFraction: 0.86, blendDuration: 0)
    public static let ambientGlowAnimation = Animation.easeInOut(duration: 8.0).repeatForever(autoreverses: true)
}
