import SwiftUI

/// Pulsing liquid-glass typing indicator bubble showing fluid bouncing dots.
public struct LiveTypingIndicatorView: View {
    @Environment(\.appTheme) private var theme
    public let userNames: [String]
    @State private var phase: Double = 0.0

    public init(userNames: [String]) {
        self.userNames = userNames
    }

    public var body: some View {
        HStack(spacing: 8) {
            // 3 fluid bouncing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                        .offset(y: bouncingOffset(for: index))
                }
            }
            .frame(height: 14)

            // Label
            Text(typingLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassPill(specularIntensity: 0.4, strokeWidth: 0.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }

    private func bouncingOffset(for index: Int) -> CGFloat {
        let delayFraction = Double(index) * 0.25
        let current = (phase + delayFraction).truncatingRemainder(dividingBy: 1.0)
        return -sin(current * .pi) * 5.0
    }

    private var typingLabel: String {
        if userNames.isEmpty {
            return "Someone is typing..."
        } else if userNames.count == 1 {
            return "\(userNames[0]) is typing..."
        } else {
            return "\(userNames.joined(separator: ", ")) are typing..."
        }
    }
}
