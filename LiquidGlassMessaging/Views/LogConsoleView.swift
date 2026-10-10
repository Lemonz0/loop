import SwiftUI

public enum LogFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case network = "NETWORK"
    case media = "MEDIA"
    case calling = "CALLING"
    case theme = "THEME"
    case errors = "ERRORS"

    public var id: String { rawValue }
}

/// Real-time diagnostic console sheet displaying color-coded log entries with filtering and export capabilities.
@MainActor
public struct LogConsoleView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var logger = AppLogger.shared
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var copiedConfirmation: Bool = false

    public init() {}

    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .network:
                matchesCategory = entry.category == .network
            case .media:
                matchesCategory = entry.category == .media
            case .calling:
                matchesCategory = entry.category == .calling
            case .theme:
                matchesCategory = entry.category == .theme
            case .errors:
                matchesCategory = entry.level == .error || entry.level == .warn
            }

            if !matchesCategory { return false }
            if searchText.isEmpty { return true }
            return entry.message.localizedCaseInsensitiveContains(searchText) ||
                   entry.category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()

                VStack(spacing: 12) {
                    filterChipsBar
                    consoleOutputArea
                    bottomControlsBar
                }
            }
            .searchable(text: $searchText, prompt: "Search diagnostic events...")
            .navigationTitle("Live Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.button)
                        .font(.system(size: 11, weight: .semibold))
                        .tint(theme.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Subviews

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LogFilter.allCases) { filter in
                    Button {
                        HapticFeedback.selection()
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)

                    }
                    .modifier(LogFilterButtonStyleModifier(isSelected: selectedFilter == filter))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private var consoleOutputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if filteredEntries.isEmpty {
                        Text("No log events found for selected filter.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .padding(24)
                    } else {
                        ForEach(filteredEntries) { entry in
                            LogLineRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .proMotionAdaptiveScroll(coordinateSpaceName: "log_console_scroll")
            }
            .coordinateSpace(name: "log_console_scroll")
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            .padding(.horizontal, 16)
            .onChange(of: filteredEntries.count) {
                if autoScroll, let last = filteredEntries.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var bottomControlsBar: some View {
        HStack(spacing: 12) {
            Text("\(filteredEntries.count) events")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.secondaryText)

            Spacer()

            Button {
                copyAllLogs()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedConfirmation ? "checkmark" : "doc.on.doc")
                    Text(copiedConfirmation ? "Copied" : "Copy")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: Capsule())
            }

            if let exportFile = logger.exportFileURL() {
                ShareLink(item: exportFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
                }
            }

            Button {
                HapticFeedback.rigid()
                logger.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.destructive)
                    .padding(7)
                    .glassEffect(.regular, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func copyAllLogs() {
        #if canImport(UIKit)
        UIPasteboard.general.string = logger.exportPlainText()
        #endif
        HapticFeedback.success()
        copiedConfirmation = true
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            copiedConfirmation = false
        }
    }
}

/// Individual row view for a color-coded log event.
private struct LogLineRow: View {
    @Environment(\.appTheme) private var theme
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.formattedTimestamp)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 68, alignment: .leading)

            Text("[\(entry.category.rawValue)]")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(categoryColor)
                .frame(width: 62, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(levelColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return theme.secondaryText
        case .info: return .primary
        case .warn: return theme.warning
        case .error: return theme.destructive
        }
    }

    private var categoryColor: Color {
        switch entry.category {
        case .network: return theme.success
        case .media: return theme.accent
        case .calling: return theme.accent
        case .theme: return theme.warning
        case .ui: return theme.accent
        case .general: return theme.secondaryText
        }
    }
}

private struct LogFilterButtonStyleModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .buttonBorderShape(.capsule)
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}
