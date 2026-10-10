import Foundation
import AVFoundation

/// Coordinates AVAudioSession category configuration, route changes (AirPods/Speaker),
/// and VoIP audio hardware management.
public final class AudioSessionCoordinator: @unchecked Sendable {
    public static let shared = AudioSessionCoordinator()
    private var isConfigured: Bool = false
    
    private init() {
        #if os(iOS)
        setupNotifications()
        #endif
    }
    
    public func startAudioSession() throws {
        try configureForCall()
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// CallKit owns activation; configure the route before fulfilling its actions.
    public func configureForCall() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try audioSession.setPreferredIOBufferDuration(0.005)
        #endif
        self.isConfigured = true
    }
    
    public func stopAudioSession() {
        guard isConfigured else { return }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.isConfigured = false
        } catch {
            print("Failed to deactivate AVAudioSession: \(error)")
        }
        #else
        self.isConfigured = false
        #endif
    }
    
    public func setSpeakerphone(enabled: Bool) throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if enabled {
            try audioSession.overrideOutputAudioPort(.speaker)
        } else {
            try audioSession.overrideOutputAudioPort(.none)
        }
        #endif
    }
    
    #if os(iOS)
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification: notification)
        }
    }
    
    private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .newDeviceAvailable:
            print("[AudioSession] Audio output route connected (e.g. AirPods)")
        case .oldDeviceUnavailable:
            print("[AudioSession] Audio output route disconnected. Fallback to default.")
            try? setSpeakerphone(enabled: true)
        default:
            break
        }
    }
    #endif
}
