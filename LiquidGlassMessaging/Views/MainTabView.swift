import SwiftUI

// MARK: - App Tabs

public enum AppTab: Int, CaseIterable, Identifiable {
    case home
    case messages
    case settings

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .messages: return "Messages"
        case .settings: return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Main Tab Container with Floating Liquid Glass Dock

@MainActor
public struct MainTabView: View {
    @Environment(\.appTheme) private var theme
    public var chatStore: ChatStore
    @State private var selectedTab: AppTab = .messages

    public init(chatStore: ChatStore) {
        self.chatStore = chatStore
    }

    private var totalUnreadCount: Int {
        chatStore.rooms.reduce(0) { $0 + $1.unreadCount }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Active Tab Content
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .messages:
                    MessagesView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Liquid Glass Dock (WhatsApp Reference)
            if chatStore.activeRoom == nil {
                FloatingGlassTabBar(
                    selectedTab: $selectedTab,
                    unreadCount: totalUnreadCount
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(GlassTheme.fluidSpring, value: selectedTab)
        .animation(GlassTheme.snappySpring, value: chatStore.activeRoom != nil)
    }
}

// MARK: - Pure Apple iOS 26 Liquid Glass Floating Dock

public struct FloatingGlassTabBar: View {
    @Environment(\.appTheme) private var theme
    @Binding public var selectedTab: AppTab
    public var unreadCount: Int
    @Namespace private var tabNamespace

    public init(selectedTab: Binding<AppTab>, unreadCount: Int = 0) {
        self._selectedTab = selectedTab
        self.unreadCount = unreadCount
    }

    public var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = selectedTab == tab

                    Button {
                        HapticFeedback.selection()
                        withAnimation(GlassTheme.fluidSpring) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 28, height: 28)

                                if tab == .messages && unreadCount > 0 {
                                    Circle()
                                        .fill(theme.success)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }

                            if isSelected {
                                Text(tab.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, isSelected ? 16 : 12)
                        .padding(.vertical, 9)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if isSelected {
                            Color.clear
                                .glassEffect(.regular.tint(theme.glassTint), in: .capsule)
                                .matchedGeometryEffect(id: "liquid_active_tab_dock", in: tabNamespace)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}
