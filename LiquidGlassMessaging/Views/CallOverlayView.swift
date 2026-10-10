import SwiftUI
import WebRTC

@MainActor
public struct CallOverlayView: View {
    @Environment(\.appTheme) private var theme
    @Bindable public var callManager = WebRTCManager.shared
    public init() {}
    private var ringing: Bool { if case .incomingRinging = callManager.callStatus { return true }; return false }
    private var status: String {
        switch callManager.callStatus {
        case .incomingRinging(_, let name): return "\(name) is calling"
        case .outgoingCalling: return "Connecting…"
        case .connected: return "\(callManager.peers.count + 1) participants"
        default: return "Call ended"
        }
    }
    public var body: some View {
        ZStack {
            AmbientGlowBackground()
            VStack(spacing: 20) {
                Text("Loop call").font(.title.bold())
                Text(status).font(.subheadline).foregroundStyle(theme.secondaryText)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        tile(name: "You", track: callManager.isCameraEnabled ? callManager.localVideo : nil, user: AuthSessionManager.shared.currentSession.map { User(id: $0.user.id, name: $0.user.displayName, avatarURL: $0.user.avatarURL, allowsTrollPosts: true) })
                        ForEach(callManager.peers) { peer in tile(name: peer.displayName, track: callManager.remoteVideo[peer.id], user: AppEnvironment.shared.chatStore.memberProfiles[peer.id]) }
                    }.padding(20)
                }
                Spacer()
                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 14) {
                        if ringing {
                            Button("Answer", systemImage: "phone.fill") { Task { await callManager.answer() } }.buttonStyle(.glassProminent).tint(theme.success).frame(minHeight: 44)
                        } else {
                            control(callManager.isMicMuted ? "mic.slash.fill" : "mic.fill", label: callManager.isMicMuted ? "Unmute" : "Mute", action: callManager.toggleMute)
                            if callManager.localVideo != nil { control(callManager.isCameraEnabled ? "video.fill" : "video.slash.fill", label: "Toggle camera", action: callManager.toggleCamera) }
                            control(callManager.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill", label: "Toggle speaker", action: callManager.toggleSpeaker)
                        }
                        Button { Task { await callManager.hangup() } } label: { Image(systemName: "phone.down.fill").frame(width: 54, height: 54) }
                            .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(theme.destructive).accessibilityLabel(ringing ? "Decline call" : "End call")
                    }.padding(14).glassEffect(.regular, in: Capsule()).padding(.bottom, 24)
                }
            }.padding(.top, 24)
        }.environment(\.profileContext, ProfileContext(source: "call_screen")).profilePresentationHost(dismissParentOnNavigate: false)
    }
    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(label)
    }
    private func tile(name: String, track: RTCVideoTrack?, user: User?) -> some View {
        VStack(spacing: 10) {
            if let track { CallVideoView(track: track).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
            else if let user { CircleAvatar(user: user, size: 80).frame(maxWidth: .infinity).frame(height: 220) }
            else { Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(theme.accent).frame(maxWidth: .infinity).frame(height: 220) }
            Text(user?.name ?? name).font(.headline).lineLimit(1).profileEntry(user?.id ?? "", name: user?.name ?? name, enabled: user != nil)
        }.padding(12).circleSurface()
    }
}
#Preview("Call · dark") { CallOverlayView().circlePreviewTheme(.aurora) }
#Preview("Call · light") { CallOverlayView().circlePreviewTheme(.daylight) }
