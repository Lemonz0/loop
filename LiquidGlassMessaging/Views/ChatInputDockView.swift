import SwiftUI
import PhotosUI
import AVFoundation

/// Floating input dock using native regular Liquid Glass,
/// and integrated PhotosPicker supporting hardware-accelerated media intake.
@MainActor
public struct ChatInputDockView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.conversationDockHeight) private var dockHeight
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding public var text: String
    public let room: ChatRoom
    public let onSendText: (String) -> Void
    public let onSendAttachment: (MediaAttachment) -> Void
    public let onTypingChanged: (Bool) -> Void

    @Namespace private var dockNamespace
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var recorder = VoiceRecorder.shared
    @State private var voiceStartTask: Task<Void, Never>?
    @State private var draftVoice: URL?
    @State private var draftDuration = 0.0
    @Environment(\.scenePhase) private var scenePhase
    private var isVoiceRecording: Bool { recorder.isRecording }
    @State private var uploadManager = MediaUploadManager.shared

    public init(
        text: Binding<String>,
        room: ChatRoom,
        onSendText: @escaping (String) -> Void,
        onSendAttachment: @escaping (MediaAttachment) -> Void,
        onTypingChanged: @escaping (Bool) -> Void
    ) {
        self._text = text
        self.room = room
        self.onSendText = onSendText
        self.onSendAttachment = onSendAttachment
        self.onTypingChanged = onTypingChanged
    }

    public var body: some View {
        let mediaPickerAccent = theme.accent
        let attachmentHeight = dockHeight
        return VStack(spacing: 8) {
            if recorder.isRecording {
                HStack {
                    Text("Recording \(Int(recorder.duration))s").monospacedDigit()
                    Spacer()
                    Button("Cancel", role: .cancel) { recorder.cancel() }.buttonStyle(.glass)
                    Button("Stop & send") { finishVoice() }.buttonStyle(.glassProminent)
                }.padding(12).circleSurface(radius: 24).padding(.horizontal, 16)
            } else if draftVoice != nil {
                HStack {
                    Text("Voice message ready")
                    Button("Retry") { sendVoice() }.buttonStyle(.glassProminent)
                    Button("Discard", role: .destructive) { discardVoice() }.buttonStyle(.glass)
                }.padding(12).circleSurface(radius: 24).padding(.horizontal, 16)
            }
            // Media compression & upload status pill
            if uploadManager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(theme.accent)
                        .scaleEffect(0.8)

                    Text(uploadManager.processingStatus)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    if uploadManager.uploadProgress > 0 {
                        Text("\(Int(uploadManager.uploadProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .liquidGlassPill(specularIntensity: 0.5)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main Floating Input Capsule
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    // Media Picker Button (Photos, GIFs, HEIC, PNG, MOV, MP4)
                    PhotosPicker(
                        selection: $selectedPhotosItem,
                        matching: .any(of: [.images, .videos, .livePhotos, .panoramas, .screenshots])
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(mediaPickerAccent)
                            .frame(width: attachmentHeight, height: attachmentHeight)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(reduceTransparency ? .regular.tint(theme.backgroundBase) : .regular.interactive(), in: Circle())
                    .glassEffectID("attachment", in: dockNamespace)
                    .accessibilityLabel("Attach a photo or video")
                    .disabled(uploadManager.isProcessing || recorder.isRecording || recorder.requestingPermission)

                    // Expandable Text Editor Area
                    HStack(spacing: 4) {
                        ZStack(alignment: .leading) {
                        if text.isEmpty {
                            Text("Message \(room.name)").lineLimit(1)
                                .font(.system(size: 15))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.leading, 20).padding(.trailing, 4)
                                .allowsHitTesting(false)
                        }

                        TextField("", text: $text, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5).multilineTextAlignment(.leading)
                            .padding(.leading, 20).padding(.trailing, 4)
                            .padding(.vertical, 4)
                            .frame(minHeight: dockHeight)
                            .onChange(of: text) { _, newValue in
                                onTypingChanged(!newValue.isEmpty)
                            }
                    }

                    // Audio Voice Note or Send Action Button
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Voice Note Trigger
                        Button {
                            toggleVoiceRecording()
                        } label: {
                            Image(systemName: isVoiceRecording ? "waveform.circle.fill" : "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isVoiceRecording ? theme.destructive : Color.primary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(uploadManager.isProcessing || recorder.requestingPermission || draftVoice != nil)
                        .accessibilityLabel(isVoiceRecording ? "Stop voice recording" : "Record voice message")
                    } else {
                        // Prominent Liquid Glass Send Button
                        Button {
                            submitText()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(theme.accent)
                        .accessibilityLabel("Send message")
                    }
                    }.padding(.trailing, 8)
                    .glassEffect(reduceTransparency ? .regular.tint(theme.backgroundBase) : .regular.interactive(), in: Capsule())
                    .glassEffectID("message", in: dockNamespace)
                }
                .padding(.horizontal, 16)
            }
        }
        .alert("Voice message", isPresented: Binding(get: { recorder.error != nil || uploadManager.lastError != nil }, set: { if !$0 { recorder.error = nil; uploadManager.lastError = nil } })) { Button("OK") { recorder.error = nil; uploadManager.lastError = nil } } message: { Text(recorder.error ?? uploadManager.lastError ?? "") }
        .onDisappear { voiceStartTask?.cancel(); recorder.cancel(); if !uploadManager.isProcessing { discardVoice() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voiceStartTask?.cancel(); recorder.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in recorder.cancel() }
        .onChange(of: selectedPhotosItem) { _, newItem in
            guard let newItem else { return }
            handleSelectedMedia(newItem)
        }
    }

    // MARK: - Handlers

    private func submitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSendText(trimmed)
        text = ""
        onTypingChanged(false)
        HapticFeedback.rigid()
    }

    private func toggleVoiceRecording() {
        if recorder.isRecording { finishVoice() } else { voiceStartTask = Task { await recorder.start() } }
        HapticFeedback.medium()
    }

    private func finishVoice() {
        guard let (file, duration) = recorder.finish() else { return }
        draftVoice = file; draftDuration = duration; sendVoice()
    }
    private func discardVoice() { if let file = draftVoice { try? FileManager.default.removeItem(at: file) }; draftVoice = nil }
    private func sendVoice() {
        guard let file = draftVoice, !uploadManager.isProcessing, let base = AuthSessionManager.shared.savedServerURL else { return }
        let token = AuthSessionManager.shared.currentSession?.token
        Task {
            do { let attachment = try await uploadManager.uploadVoice(file: file, duration: draftDuration, serverURL: base); guard AuthSessionManager.shared.currentSession?.token == token else { discardVoice(); return }; onSendAttachment(attachment); discardVoice() }
            catch { uploadManager.lastError = error.localizedDescription }
        }
    }
    private func handleSelectedMedia(_ item: PhotosPickerItem) {
        Task { @MainActor in
            do {
                let serverURL = AppEnvironment.shared.serverBaseURL
                let token = AuthSessionManager.shared.currentSession?.token
                let attachment = try await uploadManager.processAndUpload(
                    item: item,
                    serverBaseURL: serverURL,
                    authToken: token
                )
                onSendAttachment(attachment)
                selectedPhotosItem = nil
                HapticFeedback.success()
            } catch {
                print("Failed to process and upload media: \(error)")
                uploadManager.lastError = error.localizedDescription
                selectedPhotosItem = nil
                HapticFeedback.error()
            }
        }
    }
}
