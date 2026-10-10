import Foundation
import WebRTC
import AVFoundation
import SwiftUI

struct CallICEServer: Codable, Sendable { let urls: [String]; let username: String?; let credential: String? }

@MainActor
final class CallMedia {
    let factory: RTCPeerConnectionFactory
    let audio: RTCAudioTrack
    var video: RTCVideoTrack?
    private var capturer: RTCCameraVideoCapturer?
    init(videoEnabled: Bool) {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        audio = factory.audioTrack(with: factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)), trackId: "loop-audio")
        if videoEnabled {
            let source = factory.videoSource()
            video = factory.videoTrack(with: source, trackId: "loop-video")
            capturer = RTCCameraVideoCapturer(delegate: source)
        }
        RTCAudioSession.sharedInstance().useManualAudio = true
    }
    func capture() async throws {
        guard let capturer else { return }
        guard let camera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }),
              let format = RTCCameraVideoCapturer.supportedFormats(for: camera).filter({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 1280 }).last else { throw URLError(.resourceUnavailable) }
        let fps = min(30, Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: camera, format: format, fps: fps) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    func stop() { capturer?.stopCapture(); audio.isEnabled = false; video?.isEnabled = false }
}

@MainActor
final class CallConnection: NSObject, RTCPeerConnectionDelegate {
    let peerID: String
    let callID: String
    weak var owner: WebRTCManager?
    var connection: RTCPeerConnection!
    private var candidates: [RTCIceCandidate] = []
    init(peerID: String, callID: String, owner: WebRTCManager, media: CallMedia, servers: [CallICEServer]) throws {
        self.peerID = peerID; self.callID = callID; self.owner = owner
        super.init()
        let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan; config.continualGatheringPolicy = .gatherContinually
        // ICE prioritizes host/STUN pairs; relay candidates remain a fallback.
        config.iceTransportPolicy = .all
        config.iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        guard let pc = media.factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self) else { throw URLError(.cannotConnectToHost) }
        connection = pc
        pc.add(media.audio, streamIds: ["loop"])
        if let video = media.video { pc.add(video, streamIds: ["loop"]) }
    }
    func description(offer: Bool) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil)
        let sdp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            let callback: @Sendable (RTCSessionDescription?, Error?) -> Void = { value, error in
                if let value { continuation.resume(returning: value) } else { continuation.resume(throwing: error ?? URLError(.cannotParseResponse)) }
            }
            if offer { connection.offer(for: constraints, completionHandler: callback) } else { connection.answer(for: constraints, completionHandler: callback) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(sdp) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
        return sdp
    }
    func remote(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(sdp) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
        for candidate in candidates { connection.add(candidate) { _ in } }; candidates = []
        if let track = connection.transceivers.first(where: { $0.mediaType == .video })?.receiver.track as? RTCVideoTrack { owner?.receivedVideo(track, from: peerID, callID: callID) }
    }
    func candidate(_ value: RTCIceCandidate) { if connection.remoteDescription == nil { candidates.append(value) } else { connection.add(value) { _ in } } }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor [weak self] in guard let self, let track = stream.videoTracks.first else { return }; owner?.receivedVideo(track, from: peerID, callID: callID) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in guard let self else { return }; owner?.connectionChanged(peerID, callID: callID, state: newState) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self] in guard let self else { return }; await owner?.sendCandidate(candidate, peerID: peerID, callID: callID) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

struct CallVideoView: UIViewRepresentable {
    let track: RTCVideoTrack
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero); view.videoContentMode = .scaleAspectFill
        context.coordinator.track = track; track.add(view); return view
    }
    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.track !== track { context.coordinator.track?.remove(view); track.add(view); context.coordinator.track = track }
    }
    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) { coordinator.track?.remove(view) }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var track: RTCVideoTrack? }
}
