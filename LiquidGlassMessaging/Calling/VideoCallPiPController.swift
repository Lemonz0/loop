import SwiftUI
import AVKit

#if canImport(UIKit) && os(iOS)
import UIKit

/// Controller facilitating system Picture-in-Picture (PiP) multitasking for active video calls.
@MainActor
public final class VideoCallPiPController: NSObject, AVPictureInPictureControllerDelegate {
    public static let shared = VideoCallPiPController()
    
    public private(set) var isPiPActive: Bool = false
    public private(set) var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    
    private var pipController: AVPictureInPictureController?
    
    override private init() {
        super.init()
    }
    
    public func setupPiP(with sourceView: UIView) {
        guard isPiPSupported else { return }
        
        if #available(iOS 15.0, *) {
            let callVC = AVPictureInPictureVideoCallViewController()
            let pipContentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: callVC
            )
            self.pipController = AVPictureInPictureController(contentSource: pipContentSource)
            self.pipController?.delegate = self
            self.pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }
    
    public func startPiP() {
        guard let pipController, !isPiPActive else { return }
        pipController.startPictureInPicture()
    }
    
    public func stopPiP() {
        guard let pipController, isPiPActive else { return }
        pipController.stopPictureInPicture()
    }
    
    public nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = true
        }
    }
    
    public nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false
        }
    }
    
    public nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isPiPActive = false
            print("Picture in Picture failed: \(error.localizedDescription)")
        }
    }
}
#else
@MainActor
public final class VideoCallPiPController {
    public static let shared = VideoCallPiPController()
    public private(set) var isPiPActive: Bool = false
    public private(set) var isPiPSupported: Bool = false
    private init() {}
    public func startPiP() {}
    public func stopPiP() {}
}
#endif
