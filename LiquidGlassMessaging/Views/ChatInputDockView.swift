import SwiftUI
import PhotosUI
import AVFoundation

/// Floating input dock using native regular Liquid Glass,
/// and integrated PhotosPicker supporting hardware-accelerated media intake.
@MainActor
public struct ChatInputDockView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var textFocused: Bool
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
    @State private var isSendingVoice = false
    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasVoice: Bool { recorder.isRecording || draftVoice != nil || isSendingVoice }
    private var primarySymbol: String { hasVoice || hasText ? "arrow.up" : "mic.fill" }
    private var composerPhase: String { uploadManager.isProcessing && !hasVoice ? "media" : isSendingVoice ? "sending" : recorder.isRecording ? "recording" : draftVoice != nil ? "draft" : hasText ? "text" : "microphone" }
    private var primaryLabel: String { isSendingVoice ? "Sending voice message" : recorder.isRecording ? "Stop recording and send voice message" : draftVoice != nil ? "Retry sending voice message" : hasText ? "Send message" : "Record voice message" }
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
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    attachmentControl
                    ComposerCapsule {
                        Group {
                            if hasVoice || uploadManager.isProcessing {
                                HStack(spacing: 8) {
                                    Image(systemName: !hasVoice ? "photo" : recorder.isRecording ? "waveform" : "waveform.circle")
                                        .font(.body).foregroundStyle(theme.accent).accessibilityHidden(true)
                                    Text(!hasVoice ? mediaStatus : isSendingVoice ? "Sending voice…" : recorder.isRecording ? "Recording \(voiceTime(recorder.duration))" : "Voice ready · \(voiceTime(draftDuration))")
                                        .font(.subheadline.monospacedDigit()).foregroundStyle(.primary).lineLimit(1)
                                }.frame(maxWidth: .infinity, minHeight: ComposerLayout.fieldHeight, alignment: .leading)
                                    .padding(.leading, ComposerLayout.leadingInset)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                                    .accessibilityElement(children: .combine)
                            } else {
                                TextField("", text: $text,
                                          prompt: Text("Message").foregroundStyle(theme.secondaryText), axis: .vertical)
                                    .font(.body).foregroundStyle(.primary).textFieldStyle(.plain)
                                    .lineLimit(1...4).multilineTextAlignment(.leading).focused($textFocused)
                                    .frame(minHeight: ComposerLayout.fieldHeight).padding(.leading, ComposerLayout.leadingInset)
                                    .onChange(of: text) { _, value in onTypingChanged(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                                    .accessibilityLabel("Message \(room.name)")
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                            }
                        }
                        ComposerActionButton(symbol: primarySymbol, label: primaryLabel) { primaryAction() }
                            .disabled(uploadManager.isProcessing || recorder.requestingPermission || isSendingVoice)
                    }.glassEffectID("message", in: dockNamespace)
                }.padding(.horizontal, 20)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: composerPhase)
        .alert("Send media", isPresented: Binding(get: { recorder.error != nil || uploadManager.lastError != nil }, set: { if !$0 { recorder.error = nil; uploadManager.lastError = nil } })) { Button("OK") { recorder.error = nil; uploadManager.lastError = nil } } message: { Text(recorder.error ?? uploadManager.lastError ?? "") }
        .onDisappear { voiceStartTask?.cancel(); recorder.cancel(); if !isSendingVoice && !uploadManager.isProcessing { discardVoice() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background || (phase != .active && recorder.isRecording) { voiceStartTask?.cancel(); recorder.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in recorder.cancel() }
        .onChange(of: selectedPhotosItem) { _, newItem in
            guard let newItem else { return }
            handleSelectedMedia(newItem)
        }
    }

    private var attachmentControl: some View {
        Group {
            if hasVoice {
                Button(role: .destructive) {
                    voiceStartTask?.cancel(); recorder.cancel(); discardVoice(); HapticFeedback.soft()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(theme.destructive)
                        .frame(width: ComposerLayout.barHeight, height: ComposerLayout.barHeight)
                }.accessibilityLabel(recorder.isRecording ? "Cancel voice recording" : "Discard voice message")
                    .disabled(isSendingVoice)
            } else {
                PhotosPicker(selection: $selectedPhotosItem, matching: .any(of: [.images, .videos, .livePhotos, .panoramas, .screenshots])) {
                    Image(systemName: "photo.on.rectangle.angled").font(.body.weight(.medium)).foregroundStyle(theme.accent)
                        .frame(width: ComposerLayout.barHeight, height: ComposerLayout.barHeight)
                }.accessibilityLabel("Attach a photo or video").disabled(uploadManager.isProcessing || recorder.requestingPermission)
            }
        }.buttonStyle(.plain)
            .glassEffect((reduceTransparency || contrast == .increased) ? .regular.tint(theme.backgroundBase) : .regular.interactive(), in: Circle())
            .glassEffectID("attachment", in: dockNamespace)
    }
    private var mediaStatus: String { uploadManager.processingStatus + (uploadManager.uploadProgress > 0 ? " · \(Int(uploadManager.uploadProgress * 100))%" : "") }
    private func voiceTime(_ duration: Double) -> String { let seconds = max(0, Int(duration)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private func primaryAction() {
        if recorder.isRecording { finishVoice() }
        else if draftVoice != nil { sendVoice() }
        else if hasText { submitText() }
        else { toggleVoiceRecording() }
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
        textFocused = false; onTypingChanged(false)
        if recorder.isRecording { finishVoice() } else { voiceStartTask = Task { await recorder.start() } }
        HapticFeedback.medium()
    }

    private func finishVoice() {
        guard let (file, duration) = recorder.finish() else { return }
        draftVoice = file; draftDuration = duration; sendVoice()
    }
    private func discardVoice() { if let file = draftVoice { try? FileManager.default.removeItem(at: file) }; draftVoice = nil }
    private func sendVoice() {
        guard let file = draftVoice, !isSendingVoice, !uploadManager.isProcessing, let base = AuthSessionManager.shared.savedServerURL else { return }
        let token = AuthSessionManager.shared.currentSession?.token
        isSendingVoice = true
        Task {
            defer { isSendingVoice = false }
            do { let attachment = try await uploadManager.uploadVoice(file: file, duration: draftDuration, serverURL: base, roomID: room.id); guard AuthSessionManager.shared.currentSession?.token == token else { discardVoice(); return }; onSendAttachment(attachment); discardVoice() }
            catch { uploadManager.lastError = error.localizedDescription }
        }
    }
    private func handleSelectedMedia(_ item: PhotosPickerItem) {
        Task { @MainActor in
            do {
                guard let serverURL = AuthSessionManager.shared.savedServerURL else { throw URLError(.userAuthenticationRequired) }
                let token = AuthSessionManager.shared.currentSession?.token
                let attachment = try await uploadManager.processAndUpload(
                    item: item,
                    serverBaseURL: serverURL,
                    authToken: token,
                    roomID: room.id
                )
                guard AuthSessionManager.shared.currentSession?.token == token else { return }
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
