import SwiftUI
import AVFoundation

@Observable @MainActor
final class VoiceRecorder {
    static let shared = VoiceRecorder()
    var isRecording = false
    var requestingPermission = false
    var duration: TimeInterval = 0
    var error: String?
    private var recorder: AVAudioRecorder?
    private var timer: Task<Void, Never>?
    func start() async {
        guard !isRecording, !requestingPermission, WebRTCManager.shared.callStatus == .idle else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled else { return }
        guard allowed else { error = "Allow microphone access in Settings to record a voice message."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("loop-voice-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder.prepareToRecord(), recorder.record() else { throw URLError(.cannotCreateFile) }
            self.recorder = recorder; duration = 0; isRecording = true
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self, self.isRecording else { return }
                    self.duration = self.recorder?.currentTime ?? 0
                    if self.duration >= 300 { self.error = "Recording reached five minutes. Tap Send to send it."; self.recorder?.pause(); return }
                }
            }
        } catch { self.error = error.localizedDescription; cancel() }
    }
    func finish() -> (URL, TimeInterval)? {
        guard let recorder else { return nil }
        let length = max(duration, recorder.currentTime), file = recorder.url
        recorder.stop(); self.recorder = nil; isRecording = false; timer?.cancel(); timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard length >= 0.3 else { try? FileManager.default.removeItem(at: file); return nil }
        return (file, length)
    }
    func cancel() { if let (file, _) = finish() { try? FileManager.default.removeItem(at: file) } }
}

struct VoiceMessageView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    let attachment: MediaAttachment
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var seeking = false
    @State private var progress: Double = 0
    @State private var error: String?
    @State private var loadAttempt = 0
    private var duration: Double { player?.duration ?? attachment.durationSeconds ?? 0 }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    guard let player else { error = nil; loadAttempt += 1; return }
                    if player.isPlaying { player.pause(); playing = false }
                    else {
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                            if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
                            playing = player.play()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { Image(systemName: player == nil && error != nil ? "arrow.clockwise" : playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).disabled(player == nil && error == nil)
                    .accessibilityLabel(player == nil && error != nil ? "Retry loading voice message" : playing ? "Pause voice message" : "Play voice message")
                if player == nil && error == nil { ProgressView() }
                Slider(value: $progress, in: 0...max(duration, 0.01), onEditingChanged: { editing in seeking = editing; if !editing { player?.currentTime = progress } })
                    .disabled(player == nil).accessibilityLabel("Voice message playback position")
                Text("\(Int(progress)) / \(Int(duration))s").font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryText)
            }
            if let error { Text(error).font(.caption).foregroundStyle(theme.destructive) }
        }.frame(minWidth: 230, maxWidth: 280)
            .task(id: "\(attachment.id)-\(loadAttempt)") {
                error = nil
                do {
                    let file: URL
                    if let local = attachment.localURL, FileManager.default.fileExists(atPath: local.path) { file = local }
                    else if let remote = attachment.remoteURL { file = try await AuthSessionManager.shared.mediaFile(remote) }
                    else { throw URLError(.fileDoesNotExist) }
                    try Task.checkCancellation()
                    player = try AVAudioPlayer(contentsOf: file); player?.prepareToPlay()
                } catch {
                    // SwiftUI cancels offscreen loads; URLSession reports those as URLError.cancelled.
                    guard !Task.isCancelled, !AccountHTTPClient.isCancellation(error) else { return }
                    self.error = error.localizedDescription
                }
            }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    if let player { if !seeking { progress = player.currentTime }; playing = player.isPlaying }
                }
            }
            .onDisappear { player?.stop(); playing = false }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause(); playing = false } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in player?.pause(); playing = false }
    }
}
#Preview("Voice message · dark") { VoiceMessageView(attachment: MediaAttachment(fileName: "voice.m4a", mimeType: "audio/mp4", byteSize: 1000, durationSeconds: 12, mediaType: .audio)).padding().circlePreviewTheme(.aurora) }
#Preview("Voice message · light") { VoiceMessageView(attachment: MediaAttachment(fileName: "voice.m4a", mimeType: "audio/mp4", byteSize: 1000, durationSeconds: 12, mediaType: .audio)).padding().circlePreviewTheme(.daylight) }
