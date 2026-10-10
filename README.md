# 💎 Liquid Glass — Private Native iOS Messaging & Real-Time Hub

A private, high-performance messaging client and server designed exclusively for a close circle of friends. Built with **100% native iOS (Swift 6 & SwiftUI)** featuring a **"Liquid Glass"** visual aesthetic (ultra-thin translucent materials, progressive blurs, and specular light borders), hardware-accelerated on-device media compression enforcing a **strict 150 MB limit**, actor-isolated WebSockets, and native **CallKit + WebRTC group audio/video calling**.

---

## 🏗️ System Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │            iOS Client (SwiftUI)              │
                    │ ┌──────────────────────────────────────────┐ │
                    │ │ "Liquid Glass" Visual Engine             │ │
                    │ │ • .ultraThinMaterial + Specular Borders  │ │
                    │ │ • Ambient Dynamic Glow Mesh Canvas       │ │
                    │ │ • Micro-interactions & Haptic Physics    │ │
                    │ └────────────────────┬─────────────────────┘ │
                    │                      │                       │
                    │ ┌────────────────────▼─────────────────────┐ │
                    │ │ Presentation Layer (@Observable Stores)  │ │
                    │ └─────────┬────────────────────┬───────────┘ │
                    │           │                    │             │
                    │ ┌─────────▼──────────┐ ┌───────▼───────────┐ │
                    │ │ Data & Auth Store  │ │ Media Pipeline    │ │
                    │ │ • Keychain Secret  │ │ • ImageIO / Jpeg  │ │
                    │ │ • Fast Memory/Disk │ │ • AVAssetExport   │ │
                    │ └────────────────────┘ └───────┬───────────┘ │
                    │                                │             │
                    │ ┌──────────────────────────────▼───────────┐ │
                    │ │ Real-Time & Calling Engines              │ │
                    │ │ • WebSocketActor (Heartbeat & Backoff)   │ │
                    │ │ • WebRTC Mesh Signaling                  │ │
                    │ │ • CallKit & Picture-in-Picture (PiP)     │ │
                    │ └────────────────────┬─────────────────────┘ │
                    └──────────────────────┼───────────────────────┘
                                           │ TLS / WSS
                                           ▼
                    ┌──────────────────────────────────────────────┐
                    │               Backend Service                │
                    │ ┌──────────────────────────────────────────┐ │
                    │ │ Node.js Fastify / TypeScript Hub         │ │
                    │ │ • Invite Key Auth: <private-bootstrap-secret>   │ │
                    │ │ • WebSocket Hub & Presence Tracking      │ │
                    │ │ • WebRTC Group Signaling (SDP/ICE)       │ │
                    │ │ • Chunked 150 MB Uploads + HTTP Ranges   │ │
                    │ └──────────────────────────────────────────┘ │
                    └──────────────────────────────────────────────┘
```

---

## 📱 iOS Client Features & Modules (`LiquidGlassMessaging/`)

### 1. Liquid Glass Design System (`DesignSystem/`)
- [`GlassTheme.swift`](LiquidGlassMessaging/DesignSystem/GlassTheme.swift): Design tokens, specular angles, fluid spring parameters, and chromatic accent glows.
- [`LiquidGlassModifier.swift`](LiquidGlassMessaging/DesignSystem/LiquidGlassModifier.swift): Custom SwiftUI ViewModifier applying `.ultraThinMaterial`, progressive blur, and `LinearGradient` specular stroke rims (`.liquidGlass()`, `.liquidGlassPill()`, `.liquidGlassBubble()`).
- [`AmbientGlowBackground.swift`](LiquidGlassMessaging/DesignSystem/AmbientGlowBackground.swift): Luminous chromatic orbs shifting behind glass surfaces to produce realistic refraction and depth.
- [`SpringHaptics.swift`](LiquidGlassMessaging/DesignSystem/SpringHaptics.swift): Haptic engine leveraging `UIImpactFeedbackGenerator` (`.soft`, `.rigid`, `.medium`) and responsive press springs.

### 2. Media Pipeline & Auto-Compression ($\le 150$ MB) (`MediaPipeline/`)
- [`MediaInspector.swift`](LiquidGlassMessaging/MediaPipeline/MediaInspector.swift): Inspects raw byte counts against the 150 MB boundary ($157{,}286{,}400$ bytes) and extracts video duration/dimensions.
- [`ImageDownsampler.swift`](LiquidGlassMessaging/MediaPipeline/ImageDownsampler.swift): Downsamples large RAW/HEIC/PNG images using `ImageIO` thumbnailing (`CGImageSourceCreateThumbnailAtIndex`) and adaptive JPEG compression to guarantee output $< 150$ MB without RAM spikes.
- [`VideoCompressor.swift`](LiquidGlassMessaging/MediaPipeline/VideoCompressor.swift):
  - If video $\le 150$ MB: uploads original file directly.
  - If video $> 150$ MB: calculates permissible maximum bitrate:
    $$\text{MaxBitrate} = \frac{(140 \times 1024 \times 1024 \times 8)}{\text{durationInSeconds}} \times 0.94$$
  - Compresses with `AVAssetExportSession` using `AVAssetExportPresetHEVCHighestQuality` or 1080p, optimizing for network streaming (`moov` atom fast-start).
- [`MediaUploadManager.swift`](LiquidGlassMessaging/MediaPipeline/MediaUploadManager.swift): Orchestrates SwiftUI `PhotosPicker` items, progress publishing, and background `URLSessionUploadTask`.
- [`InlineMediaView.swift`](LiquidGlassMessaging/MediaPipeline/InlineMediaView.swift): Inline frosted-glass `AVPlayer` card and interactive **drag-to-dismiss** full-screen media sheet with rubber-banding physics.

### 3. Real-Time Networking Engine (`Networking/`)
- [`WebSocketActor.swift`](LiquidGlassMessaging/Networking/WebSocketActor.swift): Thread-safe Swift Actor managing `URLSessionWebSocketTask`, 25s heartbeat pings, exponential reconnect backoff with jitter, and `AsyncStream<ServerMessageEnvelope>`.
- [`ChatStore.swift`](LiquidGlassMessaging/Networking/ChatStore.swift): `@Observable @MainActor` state store managing room lists, live typing indicators (with 3.5s auto-reset debounce), message delivery states (`sending` $\to$ `sent` $\to$ `delivered` $\to$ `read`), and presence updates.
- [`AuthSessionManager.swift`](LiquidGlassMessaging/Networking/AuthSessionManager.swift): Closed-circle authentication coordinator managing Keychain credentials and secret key handshake.

### 4. Group Calling & System Telephony (`Calling/`)
- [`CallKitManager.swift`](LiquidGlassMessaging/Calling/CallKitManager.swift): `CXProviderDelegate` & `CXCallController` integration enabling full native iOS lock-screen answering, call logs, and telecom-grade mute handling.
- [`AudioSessionCoordinator.swift`](LiquidGlassMessaging/Calling/AudioSessionCoordinator.swift): Configures `AVAudioSession` (`.playAndRecord`, mode: `.voiceChat`, options: `[.allowBluetooth, .defaultToSpeaker]`) with automatic AirPods route handoff.
- [`WebRTCManager.swift`](LiquidGlassMessaging/Calling/WebRTCManager.swift): Peer negotiation, SDP offer/answer exchange, ICE forwarding, and track states.
- [`VideoCallPiPController.swift`](LiquidGlassMessaging/Calling/VideoCallPiPController.swift): Native Picture-in-Picture support with `AVPictureInPictureVideoCallViewController` for floating video calls while multitasking.

### 5. Liquid Glass SwiftUI Views (`Views/`)
- [`ChatInputDockView.swift`](LiquidGlassMessaging/Views/ChatInputDockView.swift): Floating pill input dock with expandable text field, photo/video picker, voice note trigger, and specular send button.
- [`MessageBubbleView.swift`](LiquidGlassMessaging/Views/MessageBubbleView.swift): Frosted glass chat bubbles with delivery checkmarks, inline media cards, and specular rim edges.
- [`LiveTypingIndicatorView.swift`](LiquidGlassMessaging/Views/LiveTypingIndicatorView.swift): Translucent capsule with 3 fluid bouncing cyan dots.
- [`ChatRoomView.swift`](LiquidGlassMessaging/Views/ChatRoomView.swift): Main scrollable chat conversation with auto-scroll and quick call actions.
- [`ChatRoomListView.swift`](LiquidGlassMessaging/Views/ChatRoomListView.swift): Conversations directory with online presence dock and frosted glass cards.
- [`CallOverlayView.swift`](LiquidGlassMessaging/Views/CallOverlayView.swift): Group call screen with video grid tiles and floating glassmorphic call controls.
- [`InviteAuthView.swift`](LiquidGlassMessaging/Views/InviteAuthView.swift): Closed-circle passcode / invite secret key entry screen.

---

## 🚀 Backend Service (`Server/`)

Lightweight, high-performance TypeScript/Node.js service with zero bloat:
- **Authentication**: password-backed accounts and private-circle invites; see [BackendAccounts](docs/BackendAccounts.md).
- **Media Ingestion**: `POST /api/media/upload` (Supports up to 150 MB streaming uploads).
- **Media Streaming**: `GET /uploads/:filename` with full **HTTP 206 Partial Content (Byte Range Requests)** support for instant video scrubbing in `AVPlayer`.
- **Real-Time Hub**: `ws://localhost:8080/ws` multiplexing instant message delivery, live typing bubbles, presence indicators, and WebRTC SDP/ICE signaling.

### Running the Server

```bash
cd Server
npm install
npm run build
npm start
```

Default endpoints:
- HTTP API: `http://localhost:8080`
- WebSocket: `ws://localhost:8080/ws`
- Health check: `http://localhost:8080/health`
- Bootstrap secret: supply privately through `Server/.env`; see [BackendAccounts](docs/BackendAccounts.md).

---

## 🛠️ Opening the iOS Project

1. Open `LiquidGlassMessaging/Package.swift` directly in Xcode (or add it as a local Swift Package to your iOS App project).
2. Set target to **iOS 17.0+** and run on iOS Simulator or physical iPhone.
3. Create or log into an account using a private invite supplied by your circle owner.
