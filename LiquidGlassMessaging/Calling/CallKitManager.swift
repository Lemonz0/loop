import Foundation
import AVFoundation

#if canImport(CallKit) && os(iOS)
import CallKit
import WebRTC

/// CallKit integration manager providing native iOS lock-screen answering,
/// telephony integration, and system audio control for group calls.
@MainActor
public final class CallKitManager: NSObject, CXProviderDelegate {
    public static let shared = CallKitManager()
    
    private let provider: CXProvider
    private let callController = CXCallController()
    private var outgoing = false
    
    public private(set) var activeCallUUID: UUID?
    public var onCallAnswered: ((UUID) -> Void)?
    public var onCallEnded: ((UUID) -> Void)?
    public var onMuteToggled: ((UUID, Bool) -> Void)?
    
    override private init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true
        
        self.provider = CXProvider(configuration: configuration)
        super.init()
        self.provider.setDelegate(self, queue: nil)
    }
    
    public func reportIncomingCall(
        uuid: UUID = UUID(),
        callerName: String,
        hasVideo: Bool = true
    ) async throws {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsDTMF = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        
        try await provider.reportNewIncomingCall(with: uuid, update: update)
        self.activeCallUUID = uuid; outgoing = false
    }
    
    public func startOutgoingCall(uuid: UUID = UUID(), recipientName: String, hasVideo: Bool = true) async throws {
        let handle = CXHandle(type: .generic, value: recipientName)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = hasVideo
        
        let transaction = CXTransaction(action: action)
        try await callController.request(transaction)
        self.activeCallUUID = uuid; outgoing = true
    }
    
    public func answerCall() async {
        guard let id = activeCallUUID else { return }
        try? await callController.request(CXTransaction(action: CXAnswerCallAction(call: id)))
    }
    public func reportConnected() {
        guard outgoing, let id = activeCallUUID else { return }
        provider.reportOutgoingCall(with: id, connectedAt: Date())
    }
    public func endCall(uuid: UUID? = nil) async {
        guard let targetUUID = uuid ?? activeCallUUID else { return }
        activeCallUUID = nil
        let endAction = CXEndCallAction(call: targetUUID)
        let transaction = CXTransaction(action: endAction)
        
        do {
            try await callController.request(transaction)
        } catch {
            provider.reportCall(with: targetUUID, endedAt: Date(), reason: .remoteEnded)
            self.activeCallUUID = nil
        }
    }
    
    public func setMuted(uuid: UUID? = nil, isMuted: Bool) async {
        guard let targetUUID = uuid ?? activeCallUUID else { return }
        let muteAction = CXSetMutedCallAction(call: targetUUID, muted: isMuted)
        let transaction = CXTransaction(action: muteAction)
        try? await callController.request(transaction)
    }
    
    public nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            AudioSessionCoordinator.shared.stopAudioSession()
            self.activeCallUUID = nil
        }
    }
    
    public nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            do {
                try AudioSessionCoordinator.shared.startAudioSession()
                action.fulfill()
                self.onCallAnswered?(action.callUUID)
            } catch {
                action.fail()
            }
        }
    }
    
    public nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            AudioSessionCoordinator.shared.stopAudioSession()
            action.fulfill()
            self.onCallEnded?(action.callUUID)
            self.activeCallUUID = nil
        }
    }
    
    public nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            action.fulfill()
            self.onMuteToggled?(action.callUUID, action.isMuted)
        }
    }
    
    public nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in
            RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = true
            try? AudioSessionCoordinator.shared.startAudioSession()
        }
    }
    
    public nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = false
            AudioSessionCoordinator.shared.stopAudioSession()
        }
    }
}
#else
@MainActor
public final class CallKitManager {
    public static let shared = CallKitManager()
    public private(set) var activeCallUUID: UUID?
    public var onCallAnswered: ((UUID) -> Void)?
    public var onCallEnded: ((UUID) -> Void)?
    public var onMuteToggled: ((UUID, Bool) -> Void)?
    
    private init() {}
    public func reportIncomingCall(uuid: UUID = UUID(), callerName: String, hasVideo: Bool = true) async throws {}
    public func startOutgoingCall(uuid: UUID = UUID(), recipientName: String, hasVideo: Bool = true) async throws {}
    public func answerCall() async {}
    public func reportConnected() {}
    public func endCall(uuid: UUID? = nil) async {}
    public func setMuted(uuid: UUID? = nil, isMuted: Bool) async {}
}
#endif
