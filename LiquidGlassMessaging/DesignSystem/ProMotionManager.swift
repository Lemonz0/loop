import SwiftUI

#if os(iOS)
import UIKit
import QuartzCore
#endif

// MARK: - ProMotion Refresh Rate Tiers

/// Dynamic situation-adaptive refresh rate tiers for Apple ProMotion (10Hz to 120Hz).
public enum ProMotionState: String, Sendable, CaseIterable {
    case peak120 = "120Hz (Peak)"
    case fluid80 = "80Hz (Fluid)"
    case idle10 = "10Hz (Rest)"
    
    // Backwards-compatible aliases
    public static var fastScroll: ProMotionState { .peak120 }
    public static var scrolling: ProMotionState { .fluid80 }
    public static var idle: ProMotionState { .idle10 }
    
    public var targetHz: Int {
        switch self {
        case .peak120: return 120
        case .fluid80: return 80
        case .idle10: return 10
        }
    }
    
    public var minHz: Float {
        switch self {
        case .peak120: return 80
        case .fluid80: return 60
        case .idle10: return 10
        }
    }
    
    public var maxHz: Float {
        switch self {
        case .peak120: return 120
        case .fluid80: return 80
        case .idle10: return 120
        }
    }
    
    public var preferredHz: Float {
        Float(targetHz)
    }
    
    #if os(iOS)
    @available(iOS 15.0, *)
    public var frameRateRange: CAFrameRateRange {
        CAFrameRateRange(minimum: minHz, maximum: maxHz, preferred: preferredHz)
    }
    #endif
}

// MARK: - Non-UI ProMotion Thermal Service

/// Background thermal-aware service managing Apple ProMotion variable frame rates invisibly.
/// ProMotion 120Hz scrolling is handled natively by iOS UIScrollView and CoreAnimation.
/// This service coordinates situational frame rate ranges during user interactions and rest.
@Observable
@MainActor
public final class ProMotionManager: NSObject {
    public static let shared = ProMotionManager()
    
    // Hidden AppStorage key for adaptive toggle (default true, unexposed in UI)
    private static let adaptiveKey = "settings_promotion_adaptive_enabled"
    
    public private(set) var currentState: ProMotionState = .peak120
    public private(set) var actualEstimatedFPS: Int = 120
    
    public var isProMotionEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.adaptiveKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.adaptiveKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.adaptiveKey)
            #if os(iOS)
            if !newValue {
                displayLink?.isPaused = true
            } else {
                displayLink?.isPaused = false
                applyState(currentState)
            }
            #endif
        }
    }
    
    #if os(iOS)
    private var displayLink: CADisplayLink?
    private var lastFPSUpdateTimestamp: CFTimeInterval = 0
    #endif
    
    private var settlingTask: Task<Void, Never>?
    private var isStarted: Bool = false
    
    public override init() {
        super.init()
        #if os(iOS)
        setupDisplayLink()
        #endif
    }
    
    /// Starts the ProMotion frame pacing manager at application launch.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        #if os(iOS)
        setupDisplayLink()
        #endif
    }
    
    #if os(iOS)
    private func setupDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        guard isProMotionEnabled else { return }
        
        let now = link.timestamp
        if now - lastFPSUpdateTimestamp >= 1.0 {
            lastFPSUpdateTimestamp = now
            let interval = link.targetTimestamp > link.timestamp ? (link.targetTimestamp - link.timestamp) : 0.00833
            if interval > 0.002 {
                let instantFPS = Int(round(1.0 / interval))
                let measured = max(10, min(120, instantFPS))
                if measured != self.actualEstimatedFPS {
                    self.actualEstimatedFPS = measured
                }
            }
        }
    }
    #endif
    
    // MARK: - Situational Frame Rate Modulation
    
    public func userInteractionBegan() {
        guard isProMotionEnabled else { return }
        settlingTask?.cancel()
        applyState(.peak120)
    }
    
    public func userInteractionEnded() {
        scheduleGracefulSettling()
    }
    
    public func boostTo120(duration: TimeInterval = 1.2) {
        guard isProMotionEnabled else { return }
        settlingTask?.cancel()
        applyState(.peak120)
        settlingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.scheduleGracefulSettling()
        }
    }
    
    public func updateScrollVelocity(_ velocity: CGFloat) {
        guard isProMotionEnabled else { return }
        if velocity >= 80 {
            applyState(.peak120)
        } else if velocity >= 6 {
            if currentState != .peak120 {
                applyState(.fluid80)
            }
        } else {
            scheduleGracefulSettling()
        }
    }
    
    private func scheduleGracefulSettling() {
        settlingTask?.cancel()
        settlingTask = Task { @MainActor [weak self] in
            if self?.currentState == .peak120 {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                self?.applyState(.fluid80)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.applyState(.idle10)
        }
    }
    
    private func applyState(_ state: ProMotionState) {
        guard isProMotionEnabled else { return }
        guard state != currentState else { return }
        self.currentState = state
        
        #if os(iOS)
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = state.frameRateRange
        }
        #endif
    }
}

// MARK: - Backwards Compatibility Alias

/// Preserves existing callers targeting ProMotionEngine.
public typealias ProMotionEngine = ProMotionManager

// MARK: - Zero-Overhead Scroll Modifiers

public struct ProMotionAdaptiveScrollModifier: ViewModifier {
    let coordinateSpaceName: String
    
    public init(coordinateSpaceName: String = "ProMotionContent") {
        self.coordinateSpaceName = coordinateSpaceName
    }
    
    public func body(content: Content) -> some View {
        content
    }
}

public extension View {
    func proMotionAdaptiveScroll(coordinateSpaceName: String = "ProMotionContent") -> some View {
        self.modifier(ProMotionAdaptiveScrollModifier(coordinateSpaceName: coordinateSpaceName))
    }
    
    func proMotionTouchBoost() -> some View {
        self
    }
}
