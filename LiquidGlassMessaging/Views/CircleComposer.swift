import SwiftUI
import PhotosUI
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

struct CircleComposer: View {
    @Environment(\.dismiss) private var dismiss
    let kind: CircleComposerKind
    @Bindable var model: CircleViewModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var media: CircleMedia?
    @State private var caption = ""
    @State private var subjects: Set<String> = []
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            if let media {
                                CircleMediaView(media: media).frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Label(isLoading ? "Loading photo…" : "Choose photo", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.glass).disabled(isLoading || isPosting)
                            TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                                .lineLimit(2...5).padding().circleSurface(radius: 20)
                            if kind == .troll {
                                Text("Who's in this photo?").font(.headline)
                                Text("Select everyone shown. Friends who opted out cannot be posted.").font(.footnote)
                                ForEach(model.snapshot.friends) { friend in
                                    Toggle(friend.name + (friend.allowsTrollPosts ? "" : " · opted out"), isOn: Binding(
                                        get: { subjects.contains(friend.id) },
                                        set: { if $0 { subjects.insert(friend.id) } else { subjects.remove(friend.id) } }))
                                        .disabled(!friend.allowsTrollPosts || isPosting).padding().circleSurface(radius: 20)
                                }
                            }
                            if let error { Text(error).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
                            Button {
                                guard let media else { return }
                                isPosting = true
                                Task {
                                    let success = await model.publish(media: media, caption: caption, kind: kind, subjects: subjects)
                                    isPosting = false
                                    if success { dismiss() } else { error = model.errorMessage; model.errorMessage = nil }
                                }
                            } label: {
                                HStack { if isPosting { ProgressView() }; Text(kind.title) }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(media == nil || isLoading || isPosting || (kind == .troll && subjects.isEmpty))
                        }
                    }.padding(20)
                }
            }
            .interactiveDismissDisabled(isPosting)
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(isPosting) } }
            .task(id: selectedItem) {
                guard let item = selectedItem else { return }
                isLoading = true; defer { isLoading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else { throw CircleRepositoryError.emptyMedia }
                    try Task.checkCancellation()
                    #if canImport(UIKit)
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary),
                          let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.9) else { throw CircleRepositoryError.emptyMedia }
                    media = CircleMedia(imageData: jpeg)
                    #else
                    media = CircleMedia(imageData: data)
                    #endif
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        }
    }
}

#Preview("Composer · dark") { CircleComposer(kind: .troll, model: CircleViewModel()).circlePreviewTheme(.aurora) }
#Preview("Composer · light") { CircleComposer(kind: .troll, model: CircleViewModel()).circlePreviewTheme(.daylight) }
