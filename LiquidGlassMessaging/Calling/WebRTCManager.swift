import Foundation
import SwiftUI
import AVFoundation
import WebRTC

public struct CallPeer: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public var isMuted = false
    public var isVideoEnabled = false
    public var isSpeaking = false
}
@Observable @MainActor
public final class WebRTCManager {
    public static let shared = WebRTCManager()
    public enum CallStatus: Equatable {
        case idle, outgoingCalling(roomId: String), incomingRinging(roomId: String, callerName: String), connected(roomId: String), ended
    }
    public var callStatus: CallStatus = .idle
    public var peers: [CallPeer] = []
    public var isMicMuted = false
    public var isCameraEnabled = false
    public var isSpeakerEnabled = true
    public var lastError: String?
    public private(set) var localVideo: RTCVideoTrack?
    public private(set) var remoteVideo: [String: RTCVideoTrack] = [:]
    private var activeCallId: String?
    private var activeRoomId: String?
    private var inviterID: String?
    private var videoCall = false
    private var preparing = false
    private var media: CallMedia?
    private var servers: [CallICEServer] = []
    private var connections: [String: CallConnection] = [:]
    private var earlyCandidates: [String: [RTCIceCandidate]] = [:]
    private var timeout: Task<Void, Never>?
    private var userID: String { AuthSessionManager.shared.currentSession?.user.id ?? "" }
    public init() {
        CallKitManager.shared.onCallAnswered = { [weak self] _ in Task { await self?.acceptIncomingCall() } }
        CallKitManager.shared.onCallEnded = { [weak self] _ in Task { await self?.hangup() } }
        CallKitManager.shared.onMuteToggled = { [weak self] _, muted in self?.isMicMuted = muted; self?.media?.audio.isEnabled = !muted }
    }
    private func prepare() async throws {
        let preparingCall = activeCallId
        guard await AVAudioApplication.requestRecordPermission() else { throw CallError.message("Allow microphone access in Settings.") }
        if videoCall, !(await AVCaptureDevice.requestAccess(for: .video)) { throw CallError.message("Allow camera access in Settings.") }
        guard let token = AuthSessionManager.shared.currentSession?.token, let base = AuthSessionManager.shared.savedServerURL else { throw URLError(.userAuthenticationRequired) }
        struct ICE: Decodable, Sendable { let servers: [CallICEServer] }
        servers = try await AccountHTTPClient.shared.request("api/calls/ice", baseURL: base, token: token, as: ICE.self).servers
        guard activeCallId == preparingCall else { throw CancellationError() }
        let local = CallMedia(videoEnabled: videoCall)
        media = local; localVideo = local.video; isCameraEnabled = videoCall; local.audio.isEnabled = !isMicMuted
        try await local.capture()
        guard activeCallId == preparingCall else { local.stop(); throw CancellationError() }
    }
    public func startCall(roomId: String, roomName: String, isVideo: Bool = true) async {
        guard callStatus == .idle, !preparing else { return }
        guard case .connected = AppEnvironment.shared.chatStore.connectionState else { lastError = "Connect to the server before calling."; return }
        VoiceRecorder.shared.cancel()
        preparing = true; defer { preparing = false }
        isMicMuted = false
        activeCallId = UUID().uuidString; activeRoomId = roomId; inviterID = userID; videoCall = isVideo
        callStatus = .outgoingCalling(roomId: roomId)
        do {
            try await prepare()
            try await CallKitManager.shared.startOutgoingCall(recipientName: roomName, hasVideo: isVideo)
            callStatus = .outgoingCalling(roomId: roomId)
            try await send(.offer)
            armTimeout()
        } catch { lastError = error.localizedDescription; await hangup() }
    }
    public func answer() async { await CallKitManager.shared.answerCall() }
    public func acceptIncomingCall() async {
        guard case .incomingRinging(let room, _) = callStatus, !preparing else { return }
        preparing = true; defer { preparing = false }
        do { try await prepare(); guard activeRoomId == room else { return }; callStatus = .outgoingCalling(roomId: room); try await send(.answer); armTimeout() }
        catch { lastError = error.localizedDescription; await hangup() }
    }
    private func armTimeout() {
        let id = activeCallId
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.activeCallId == id else { return }
            if case .connected = self.callStatus { return }
            self.lastError = "The call could not connect. Both phones must have Loop open; some networks require a TURN relay."
            await self.hangup()
        }
    }
    public func hangup() async {
        guard activeCallId != nil else { return }
        try? await send(.hangup)
        activeCallId = nil; activeRoomId = nil; inviterID = nil; callStatus = .idle
        timeout?.cancel(); connections.values.forEach { $0.connection.close() }; connections = [:]; earlyCandidates = [:]
        media?.stop(); media = nil; localVideo = nil; remoteVideo = [:]; peers = []
        await CallKitManager.shared.endCall()
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        AudioSessionCoordinator.shared.stopAudioSession()
    }
    public func toggleMute() { isMicMuted.toggle(); media?.audio.isEnabled = !isMicMuted; Task { await CallKitManager.shared.setMuted(isMuted: isMicMuted) } }
    public func toggleCamera() { guard videoCall else { return }; isCameraEnabled.toggle(); localVideo?.isEnabled = isCameraEnabled }
    public func toggleSpeaker() { isSpeakerEnabled.toggle(); try? AudioSessionCoordinator.shared.setSpeakerphone(enabled: isSpeakerEnabled) }
    private func send(_ type: CallSignalType, target: String? = nil, sdp: String? = nil, candidate: RTCIceCandidate? = nil) async throws {
        guard let call = activeCallId, let room = activeRoomId else { return }
        let signal = CallSignalPayload(callId: call, roomId: room, senderId: userID, targetId: target, signalType: type,
            sdp: sdp, sdpMid: candidate?.sdpMid, sdpMLineIndex: candidate?.sdpMLineIndex, candidate: candidate?.sdp, isVideo: videoCall)
        try await AppEnvironment.shared.chatStore.webSocketActor.send(envelope: ClientMessageEnvelope(type: .callSignal, roomId: room, callSignal: signal))
    }
    private func peer(_ id: String) throws -> CallConnection {
        if let existing = connections[id] { return existing }
        guard let call = activeCallId, let media else { throw CallError.message("Call media is unavailable.") }
        let pc = try CallConnection(peerID: id, callID: call, owner: self, media: media, servers: servers)
        connections[id] = pc
        for candidate in earlyCandidates.removeValue(forKey: id) ?? [] { pc.candidate(candidate) }
        return pc
    }
    public func handleSignalingPayload(_ signal: CallSignalPayload) async {
        guard signal.senderId != userID, signal.targetId == nil || signal.targetId == userID else { return }
        if signal.signalType == .offer, signal.sdp == nil, callStatus == .idle, !preparing {
            guard AppEnvironment.shared.chatStore.rooms.contains(where: { $0.id == signal.roomId }) else { return }
            isMicMuted = false
            activeCallId = signal.callId; activeRoomId = signal.roomId; inviterID = signal.senderId; videoCall = signal.isVideo
            let name = AppEnvironment.shared.chatStore.presenceByUserId[signal.senderId]?.displayName ?? "Loop friend"
            callStatus = .incomingRinging(roomId: signal.roomId, callerName: name)
            do { try await CallKitManager.shared.reportIncomingCall(callerName: name, hasVideo: signal.isVideo); armTimeout() }
            catch { lastError = error.localizedDescription; await hangup() }
            return
        }
        guard signal.callId == activeCallId, signal.roomId == activeRoomId else { return }
        do {
            switch signal.signalType {
            case .answer:
                if let sdp = signal.sdp { try await peer(signal.senderId).remote(RTCSessionDescription(type: .answer, sdp: sdp)) }
                else if media != nil, connections[signal.senderId] == nil {
                    let pc = try peer(signal.senderId), call = activeCallId
                    let offer = try await pc.description(offer: true)
                    guard activeCallId == call else { return }; try await send(.offer, target: signal.senderId, sdp: offer.sdp)
                }
            case .offer:
                if let sdp = signal.sdp, media != nil {
                    let pc = try peer(signal.senderId), call = activeCallId
                    try await pc.remote(RTCSessionDescription(type: .offer, sdp: sdp)); let answer = try await pc.description(offer: false)
                    guard activeCallId == call else { return }; try await send(.answer, target: signal.senderId, sdp: answer.sdp)
                }
            case .iceCandidate:
                if let sdp = signal.candidate { let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: signal.sdpMLineIndex ?? 0, sdpMid: signal.sdpMid)
                    if let pc = connections[signal.senderId] { pc.candidate(candidate) } else { earlyCandidates[signal.senderId, default: []].append(candidate) }
                }
            case .hangup:
                let hadConnection = connections[signal.senderId] != nil
                connections.removeValue(forKey: signal.senderId)?.connection.close(); remoteVideo.removeValue(forKey: signal.senderId); peers.removeAll { $0.id == signal.senderId }
                if connections.isEmpty && (hadConnection || signal.senderId == inviterID) { await hangup() }
            case .ping: break
            }
        } catch { lastError = error.localizedDescription; await hangup() }
    }
    func sendCandidate(_ candidate: RTCIceCandidate, peerID: String, callID: String) async { guard callID == activeCallId else { return }; try? await send(.iceCandidate, target: peerID, candidate: candidate) }
    func receivedVideo(_ track: RTCVideoTrack, from id: String, callID: String) { guard callID == activeCallId, videoCall else { return }; remoteVideo[id] = track }
    func connectionChanged(_ id: String, callID: String, state: RTCIceConnectionState) {
        guard callID == activeCallId else { return }
        if state == .connected || state == .completed {
            if !peers.contains(where: { $0.id == id }) { peers.append(CallPeer(id: id, displayName: AppEnvironment.shared.chatStore.presenceByUserId[id]?.displayName ?? "Friend", isVideoEnabled: videoCall)) }
            if let room = activeRoomId { callStatus = .connected(roomId: room) }; timeout?.cancel(); CallKitManager.shared.reportConnected()
        } else if state == .failed { lastError = "Media connection failed. This network may need a TURN relay."; Task { await hangup() } }
    }
}
private enum CallError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
