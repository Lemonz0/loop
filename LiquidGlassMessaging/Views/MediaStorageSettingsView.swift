import SwiftUI

/// Focused sub-page for storage limits, cache inspection, and cache purge operations using Liquid Glass.
@MainActor
public struct MediaStorageSettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var cachedMediaSizeFormatted: String = "Calculating..."
    @State private var isClearingCache: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var logger = AppLogger.shared

    public init() {}

    public var body: some View {
        ZStack {
            AmbientGlowBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Media Limits Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MEDIA LIMITS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            LabeledContent {
                                Text("≤ 150 MB")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.success)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Auto-Compression Boundary")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Enforced hardware limit per attachment.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }

                    // Device Storage Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DEVICE STORAGE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 6)

                        GlassEffectContainer(spacing: 14) {
                            VStack(spacing: 14) {
                                // Cache Size Card
                                LabeledContent {
                                    Text(cachedMediaSizeFormatted)
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.primary)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Cached Media Files")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Text("Offline previews, voice notes, and downloads.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                                // Clear Cache Card Button
                                Button(role: .destructive) {
                                    showClearConfirmation = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Spacer()
                                        if isClearingCache {
                                            ProgressView()
                                                .tint(theme.destructive)
                                        } else {
                                            Image(systemName: "trash.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        Text("Clear Media Cache")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Spacer()
                                    }
                                    .foregroundStyle(theme.destructive)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isClearingCache)
                                .glassEffect(.regular.interactive().tint(theme.destructive.opacity(0.12)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }

                    // Footer explanatory card
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.secondaryText)
                        Text("Hardware AVFoundation auto-scales large videos to strictly enforce the ≤ 150 MB boundary. Purging cache removes offline copies.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }
            .scrollEdgeEffectStyle()
        }
        .navigationTitle("Media & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear Cached Media Files?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                clearMediaCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will purge all cached temporary images, videos, and voice memos from this device.")
        }
        .onAppear {
            calculateCacheSize()
        }
    }

    // MARK: - Cache Calculation & Clearing

    private func calculateCacheSize() {
        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }

            var totalSize: Int64 = 0
            if let enumerator = fileManager.enumerator(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }

            let formatted = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            await MainActor.run {
                self.cachedMediaSizeFormatted = formatted
            }
        }
    }

    private func clearMediaCache() {
        isClearingCache = true
        HapticFeedback.rigid()
        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? fileManager.removeItem(at: cacheURL)
                try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            }

            await MainActor.run {
                self.cachedMediaSizeFormatted = "0 KB"
                self.isClearingCache = false
                AppLogger.shared.info(.media, "Purged local media cache storage.")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MediaStorageSettingsView()
    }

}
