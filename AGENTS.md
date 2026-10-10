# AGENTS.md — Development Guidelines & Rules for Liquid Glass Messaging

Welcome to **Liquid Glass Messaging**. This file provides instructions, rules, real file paths, scheme information, and CI workflow specifications for AI coding agents operating on this repository.

---

## 1. Project Specifications

- **Platform & Target:** iOS 26.0+ (Xcode 26 SDK)
- **Primary Language:** Swift 5.9+ / SwiftUI
- **Xcode Project Scheme:** `LiquidGlass`
- **Xcode Project File:** `LiquidGlass.xcodeproj` (generated dynamically from `project.yml` via XcodeGen)
- **CI Workflow File:** `.github/workflows/ci.yml`
- **Backend Hub:** Node.js 22 + TypeScript WebSocket server in `./Server`

---

## 2. Directory Structure & Real File Paths

| Directory | Purpose | Key Files |
| :--- | :--- | :--- |
| `LiquidGlassMessaging/App/` | App lifecycle and global logging | `LiquidGlassMessagingApp.swift`, `AppEnvironment.swift`, `AppLogger.swift` |
| `LiquidGlassMessaging/DesignSystem/` | Themes, glass modifiers, and frame pacing | `LiquidGlassModifier.swift`, `ThemeManager.swift`, `GlassTheme.swift`, `AmbientGlowBackground.swift`, `ProMotionManager.swift` |
| `LiquidGlassMessaging/Views/` | All SwiftUI screens, cards, and modals | `SettingsRootView.swift`, `ProfileCard.swift`, `AppearanceSettingsView.swift`, `NotificationsSettingsView.swift`, `MediaStorageSettingsView.swift`, `ConnectionSettingsView.swift`, `DeveloperSettingsView.swift`, `HomeView.swift`, `MessagesView.swift`, `ChatRoomListView.swift`, `ChatRoomView.swift` |
| `LiquidGlassMessaging/Models/` | Core data models | `AuthModels.swift`, `ChatModels.swift` |
| `LiquidGlassMessaging/Networking/` | Networking & WebSocket actors | `ChatStore.swift`, `WebSocketActor.swift`, `AuthSessionManager.swift`, `ChatNetworkingTypes.swift` |
| `LiquidGlassMessaging/MediaPipeline/` | Video compression and image processing | `VideoCompressor.swift`, `ImageDownsampler.swift`, `MediaUploadManager.swift`, `InlineMediaView.swift` |
| `LiquidGlassMessaging/Calling/` | WebRTC audio/video and CallKit | `WebRTCManager.swift`, `CallKitManager.swift`, `AudioSessionCoordinator.swift`, `VideoCallPiPController.swift` |
| `docs/` | Architecture and reference documentation | `HANDOFF.md`, `LiquidGlassNotes.md` |
| `.github/workflows/` | Continuous integration and deployment | `ci.yml`, `deploy-server.yml` |

---

## 3. Core Development Rules

### Rule 1: Authentic Liquid Glass SDK Only
- **Zero Fake Glass:** Never use `.ultraThinMaterial`, `UIBlurEffect`, `.blur()`, simulated linear gradient borders, or hand-drawn drop shadows.
- **Native Modifiers:** Always use Apple's real iOS 26 `.glassEffect(_:in:)` API with `.regular`, `.clear`, `.tint()`, and `.interactive()`.
- **Button Styles:** Use `.buttonStyle(.glass)` for secondary buttons and `.buttonStyle(.glassProminent)` for primary actions.

### Rule 2: Spacing & Container Hierarchy
- **No Tight Platters:** Avoid grouping separate cards into tight SwiftUI `List` or `Form` sections with `.listRowBackground`, which compresses rows together with zero vertical gap.
- **Spacious Layouts:** Group adjacent glass surfaces inside `GlassEffectContainer(spacing: 14)` on a `ScrollView` with `VStack(spacing: 14)`. This gives each card a distinct 14pt gap, exposing specular edge reflections.
- **Circle Tab Bar:** The user explicitly requested native `.tabBarMinimizeBehavior(.onScrollDown)` for Circle on 2026-10-09; this supersedes the earlier stability rule. `GlassTabBar` owns the single TabView (Home, Chats, Settings, Profile). Do not nest another tab bar in Messages.

### Rule 3: Centralized Themes & Contrast
- Presets are Onyx (unchanged persisted value and #000000 base), Aurora (dark mesh), and Daylight (light mesh).
- All literal palette colors belong in `DesignSystem/ThemePalette.swift`; SwiftUI tokens and `EnvironmentValues.appTheme` belong in `DesignSystem/AppTheme.swift`.
- Read `@Environment(\.appTheme)` in views. The app root injects the active theme, color scheme, and tint. Do not force dark mode in descendants.
- Every screen and sheet uses `AmbientGlowBackground`. Only Onyx requires a black base; do not hard-code black backgrounds for Aurora or Daylight.
- Use semantic primary text and `theme.secondaryText` for supporting labels. Daylight deliberately promotes supporting text to primary to pass 4.5:1. Never hard-code white/black text or faded status colors.
- Keep text-heavy surfaces on native regular glass. Never add opaque contrast fills, hand-drawn borders, or shadows. Native prominent buttons own their label styling.
- Preserve `liquidglass_active_preset` and Onyx's raw value. Migrate both legacy labels and wire names: slate -> Aurora, frost -> Daylight; unknown -> Onyx.
- Run `node scripts/check-theme-contrast.cjs`; regenerate `docs/ThemeContrast.md` with `--write-doc` after palette changes. CI also runs the hostless `ThemeContrastTests` target on an iOS 26 simulator using the `ThemeContrast` scheme.
- Palette checks are not rendered glass certification. Retain an iOS visual check for system glass, media overlays, accessibility settings, sheets, toolbars, and tab bars.

### Rule 4: Hidden ProMotion Frame Pacing
- All display link and refresh rate logic must remain strictly inside `ProMotionManager.swift` (`CADisplayLink` at 120Hz/80Hz/10Hz).
- Never add ProMotion UI controls, FPS badges, or refresh rate pickers back to user-facing screens.
- Ensure `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone: YES` remains set in `project.yml`.

### Rule 5: Concurrency & MainActor Isolation
- `AppLogger` and `ThemeManager` are `@MainActor`-isolated classes.
- Any background worker or detached task (`Task.detached`) calling these classes must wrap the call in `await MainActor.run`.

### Rule 6: CI & Compilation Safety
- User workflow preference: always commit and push completed project changes to GitHub for testing, then inspect CI results; the user explicitly authorized this on 2026-10-09. The current workflow runs on `main`.
- The project is compiled remotely via GitHub Actions on a `macos-15` runner using Xcode 26.
- Always check delimiter balance (braces `{}`, parentheses `()`, brackets `[]`) across modified files before pushing.
- In case of build failure, inspect the exact error in the GitHub Actions job log (`.github/workflows/ci.yml`). Never guess or invent APIs.

### Circle social screens
- Social models and FeedRepository use Sendable payloads and actor isolation; view models are @Observable @MainActor. The installed app uses RemoteFeedRepository; MockFeedRepository is for previews/tests. The backend enforces membership/consent/expiry and retains Troll Wall authorship server-side only. Never add an author field to TrollPost.
- ProfileCard now lives in the separate Profile tab. Settings contains the existing settings pages and the Troll Wall consent toggle.
- Story rings are decorative status rings requested by the user, not imitation glass borders. Native glassEffectID handles the Home selection pill.
- Every new Circle view has dark/light previews. Keep semantic text and theme palette propagation, reduce-motion-safe transitions, and 44pt icon targets.

### Loop branding
- The user-facing app name is Loop. Keep the LiquidGlass target/scheme and existing signing bundle IDs for compatibility and in-place upgrades.
- Primary icon: LiquidGlassMessaging/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png, prepared from output/branding/circle-icon-v2.png as an opaque 1024x1024 RGB PNG. project.yml includes Resources and sets ASSETCATALOG_COMPILER_APPICON_NAME to AppIcon.
- The local signing script must use -n "Loop" so re-signing preserves the requested display name. OTA titles also use Loop.

### Real account integration
- AuthSessionManager validates server-bound Keychain sessions; never restore guest/default accounts or offline invite bypasses. Auth HTTP and WebSocket date decoding uses AccountCodec for JavaScript millisecond timestamps.
- ChatStore mock rooms are preview-only. Real group rooms come from authenticated circle membership. Private media uses same-origin bearer requests; logout clears chat state and private cache files.
- The user authorized running the temporary backend on this PC for same-Wi-Fi testing. Server/.env and Server/.local bootstrap codes are private and never committed or put in the app bundle. Local HTTP exceptions are scoped to local networking; hosted endpoints require HTTPS.

### Live social backend
- Select circle scope explicitly; never populate production feeds with MockData. Keep snapshot generation guards when switching circles.
- Social uploads use server-side image sanitization; anonymous media gets a separate URL and cannot be reused as an identified post/avatar. TrollPost must stay author-free.
- Consent is server-authoritative. Do not post stale local settings during refresh. Stories expire on server reads/writes and story-only media access.
- Private replies are visible only to the recipient; reports/removal are circle-owner-only without exposing anonymous uploader identities.
- Private social.json and upload data remain ignored by Git. Keep existing accounts/passwords when restarting the PC backend.

### Clean public repository
- Development/CI now uses https://github.com/Lemonz0/loop on main, with a fresh source-only history. Lemonz0/messaging stays private. Never push its old history into the public repository.
- The former local Git directory is retained privately at Server/.local/private-repository-history.git. Private accounts, uploads, chat history, environment files, and signing materials remain ignored and must never be published.
