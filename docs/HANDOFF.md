# Project Handoff: Liquid Glass Messaging (iOS 26)

## Current architecture

Native SwiftUI messaging, calling, and media sharing client, backed by the Node.js 22/TypeScript WebSocket server in `Server/`. The iOS target is 26.0, built with Xcode 26 using `project.yml`/XcodeGen and the `LiquidGlass` scheme.

Settings retains the modular `SettingsRootView`, `ProfileCard`, and five sub-pages (Appearance, Notifications, Media & Storage, Connection, Developer). Preserve `ScrollView`, `VStack(spacing: 14)`, and native `GlassEffectContainer(spacing: 14)`. The compatibility container now forwards to `SwiftUI.GlassEffectContainer`, rather than merely returning its content. Keep the native tab bar stable; never add `.tabBarMinimizeBehavior(.onScrollDown)`.

## Theme rework (2026-10-09)

- `DesignSystem/ThemePalette.swift` contains `ThemePreset`, persistence migration, sRGB hex palette definitions, and WCAG luminance/contrast arithmetic.
- `DesignSystem/AppTheme.swift` exposes `colorScheme`, `backgroundBase`, `meshColors`, `accent`, `success`, `destructive`, `warning`, `glassTint`, `secondaryText`, and `wallpaperScrim` through `EnvironmentValues.appTheme`.
- `App/LiquidGlassMessagingApp.swift` injects the selected theme and color scheme and applies `.preferredColorScheme` and `.tint` at the root.
- `DesignSystem/AmbientGlowBackground.swift` is the shared background for screens and sheets. Onyx has no mesh and remains true #000000. Aurora and Daylight use a 3x3 MeshGradient with restrained colors and `smoothsColors: false` to avoid cubic color overshoot.
- Room wallpaper selection/upload/broadcast remains available. A 96% scheme-aware scrim bounds contrast over arbitrary photographs. Built-in backgrounds follow the global selection so screens stay consistent; stored room presets are still decoded/migrated. Wallpaper scrim strength was increased for contrast.
- `Views/AppearanceSettingsView.swift` has three selection rows, native regular glass, checkmarks, one-line descriptions, and miniature color swatches. The prior OLED toggle was ineffective (all backgrounds were black regardless) and has been removed so it cannot compete with the three presets. No additional settings were added.
- `GlassTheme.swift` now contains only geometry and animation tokens. Literal foreground palettes, simulated specular strokes, and manual shadows were removed from the theme-dependent UI. All interactive surfaces use genuine native glass.

| Theme | Scheme | Base | Violet/blue, teal/lavender, blue/peach mesh | Accent | Success | Destructive | Warning |
|---|---|---|---|---|---|---|---|
| Onyx (Pure OLED Black) | Dark | #000000 | None | #70B8FF | #58DCA0 | #FF8A96 | #F2CC70 |
| Aurora (Deep Color) | Dark | #080E24 | #24203F, #103238, #152D50 | #70B8FF | #58DCA0 | #FF8A96 | #F2CC70 |
| Daylight (Light Glass) | Light | #FAF9F6 | #DFECFA, #EBE3F6, #FAE5D9 | #174E9C | #12643F | #A11D36 | #795000 |

Onyx's existing raw stored value remains `Onyx (Pure OLED Black)` and its pure-black/no-mesh behavior is preserved. UI foregrounds/status colors were corrected across all themes to satisfy the contrast request; old literal colors and decorative avatars are not retained unchanged.

Persistence retains `liquidglass_active_preset`. Both `slate` and `Slate (Neutral Grey)` migrate to Aurora; both `frost` and `Frost (Light Glass)` migrate to Daylight. Current labels and short names are accepted. Nil/unknown values fall back to Onyx. Canonical labels are written back on startup. The obsolete `liquidglass_pure_oled_black` preference is ignored.

Views use semantic `.primary` and `theme.secondaryText`: dark supporting labels use `.secondary`, while Daylight uses `.primary`. Standard light secondary text failed the requested 4.5:1 target, so it must not be reintroduced for small labels. Native prominent buttons manage their own foreground; explicit black/white overrides would defeat label adaptation.

Audited: Settings root/profile/all five sub-pages, Home, Messages and its contact/chat rows, alternate room list, floating tab bar, chat header/composer/bubbles/typing, authentication, call tiles, console, all custom sheets, media, and cache confirmation dialog. Networking, cache actions, media upload, calling, and navigation logic are preserved.

## Verification

Initial theme revision `734f3d4` passed GitHub Actions run `37941709331` with Xcode 26.3: both XCTest cases passed (0 failures), Release archive succeeded, backend build/container checks passed, and the IPA artifact uploaded. A follow-up captures the photo-picker accent before its Sendable label closure to remove the newly introduced MainActor warning. Unrelated pre-existing media/calling/concurrency and bundle-identifier warnings remain outside this task.

User workflow preference: always commit and push completed project changes to GitHub for CI testing; explicit authorization was given on 2026-10-09. Preserve this preference across future work.

- `node scripts/check-theme-contrast.cjs` reads production colors, checks contrast, and verifies the checked-in documentation table. Use `--write-doc` to regenerate `docs/ThemeContrast.md`.
- `Tests/ThemeContrastTests.swift` compiles with the production palette in a hostless iOS unit-test target. It checks persistence and Onyx invariants, actual resolved UIKit primary/supporting labels, and accent/status ratios over all bases/mesh vertices, the conservative RGB envelope, and arbitrary wallpaper extremes after the scrim.
- `project.yml` defines `ThemeContrastTests` and the `ThemeContrast` scheme. CI chooses an available iOS 26 iPhone simulator, runs `xcodebuild test`, and then archives `LiquidGlass`.
- The local workstation is Windows and cannot compile or render SwiftUI. Arithmetic checks and source review do not replace the Xcode build, XCTest execution, or visual checks of composited glass. See `docs/ThemeContrast.md` for exact ratios and limitations.

## Build and distribution

`.github/workflows/ci.yml` uses `macos-15`, selects Xcode 26, installs XcodeGen, generates the project, patches objectVersion to 56 for compatibility, runs contrast tests, archives Release without signing, packages the app into `LiquidGlassMessaging.ipa`, and uploads the IPA artifact. Backend CI compiles TypeScript and builds the Docker container. `.github/workflows/deploy-server.yml` handles backend deployment.

If CI fails, inspect exact job logs rather than guessing APIs. GitHub log downloads redirect to Azure Blob Storage; remove Authorization when following the signed redirect. Check delimiter balance before pushing. Palette/contrast CI status must be verified for the new revision before claiming a successful build.

### Automated Over-The-Air (OTA) Phone Installation Pipeline

The project uses a complete end-to-end pipeline to compile, download, re-sign, and automatically deploy the app to the user's iPhone via wireless OTA (Safari one-tap installation):

```
[Git Push to main] 
       │
       ▼
[GitHub Actions (macos-15 / Xcode 26)] ──► Compiles Release Archive & Uploads LiquidGlassMessaging.ipa
       │
       ▼
[scratch/wait_and_download.ps1] ─────────► Polls CI run, downloads artifact, extracts to Desktop\LiquidGlassMessaging.ipa
       │
       ▼
[scratch/sign_both.js] ──────────────────► Uses scratch/zsign.exe + developer .p12 & .mobileprovision
       │                                   Produces: scratch/LiquidGlass_Signed.ipa & scratch/LiquidGlass_Chat.ipa
       ▼
[scratch/ota_server.js (port 8089)] ─────► Serves /manifest.plist, /manifest-chat.plist, and IPA binaries
       │
       ▼
[Cloudflare Tunnel (cloudflared.exe)] ───► Exposes port 8089 over valid HTTPS (e.g. trycloudflare.com)
       │
       ▼
[iPhone Mobile Safari] ──────────────────► User visits HTTPS link, taps "Install Liquid Glass"
                                           Triggers itms-services://?action=download-manifest&url=...
                                           iOS downloads and installs app directly onto home screen!
```

#### Local distribution

1. Commit and push completed changes to `main`, then verify CI succeeds.
2. Run the privately configured `wait_and_download.ps1` to retrieve the unsigned IPA.
3. Run the private `sign_both.js` script to produce the two signed variants, preserving the Loop display name and existing bundle identifiers.
4. The private OTA server serves the signed files and matching manifests on port 8089 through a trusted HTTPS tunnel. Read the current tunnel address from private runtime configuration.

Signing certificates, provisioning profiles, passwords, device identifiers, absolute personal paths, and live tunnel addresses belong only in ignored local configuration. Never put them in public documentation or Git history.

## Other development rules

- Native iOS 26 `.glassEffect`, `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` only; no Materials, UIBlurEffect, `.blur()`, artificial border gradients, or drop shadows.
- Keep display-link pacing exclusively in `ProMotionManager.swift`, with no FPS/refresh controls in UI. Preserve `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone: YES`.
- `AppLogger` and `ThemeManager` are MainActor-isolated; detached tasks access them via `await MainActor.run`.
- New screens inherit the theme and use the shared background. Black is an Onyx requirement, not a global requirement for every preset.

## Next steps

1. Run and inspect CI for this revision; check every screen visually on iOS 26 in all three themes, including accessibility variations and arbitrary media under glass.
2. Keep theme changes centralized and regenerate the contrast documentation after color edits.
3. Optional future work: WebRTC packet-loss telemetry and avatar cropping.

## Circle social screens (2026-10-09)

The app root now presents GlassTabBar: Home, Chats, Settings, and a separate Profile category retaining the original ProfileCard information and editing behavior. MessagesView is a standalone chat screen inside Chats. Native scroll minimization was explicitly requested and supersedes the older no-minimization rule. Settings retains Appearance and the other existing settings pages, plus the persisted Troll Wall consent toggle.

New files: Models/SocialModels.swift and MockData.swift; Networking/FeedRepository.swift, CircleViewModel.swift, StoryViewerModel.swift; Views/StoriesRow.swift, PostCard.swift, TrollWallView.swift, StoryViewer.swift, CircleComposer.swift, GlassTabBar.swift, SocialComponents.swift. XcodeGen directory sources include them automatically.

Home has stories filtered by expiry every second, a native morphing Feed/Troll Wall control, image posts with paged media, comments/likes, search, and creation menus. Troll Wall has a two-column masonry layout, reactions, report menus, and photo posting with consent-checked subject selection. StoryViewer provides five-second progression, previous/next, hold and explicit pause, scene/keyboard pauses, swipe dismissal, private replies, and likes. VoiceOver adds explicit navigation and starts paused. Reduce Motion disables custom spring transitions; Reduce Transparency uses native regular glass with theme tint.

All new views have dark/light #Preview configurations. Screenshot layouts are implemented in SwiftUI using native glass; Onyx stays black, Aurora supplies restrained color refraction, and Daylight remains light. Top story chrome uses a dark local color scheme over its dark media scrim; the rest inherits the selected theme.

The social FeedRepository is an actor-backed in-memory mock. Posts/replies/reports are not sent to the messaging server and reset on process restart, except the local consent preference. Mock sample photos use picsum.photos; personal selected photos remain local. A production repository must authenticate every request, enforce private-circle membership and all pictured subjects' consent, return only active stories, and store moderation authorship server-side. TrollPost has no authorship field or rendering path. Public protocol methods provide the backend integration seam.

CI now runs additional tests for author-free payloads, consent enforcement, reactions, empty subject rejection, story expiry/24-hour lifetime, and viewer pause/progression before the Release archive. Native previews require Xcode/iOS visual QA; CI compilation and behavioral tests are not screenshot validation. Always complete CI -> download -> both signatures -> public OTA hash verification before delivering the installation URL.

Circle initial revision ab65289 passed run 37949055098: all 10 tests succeeded and the iOS archive/IPA and backend checks passed. Social error alerts are owned by the tab root to avoid competing presentations. Existing legacy calling/media warnings remain outside this screen implementation.

Navigation update: the standalone Troll tab was removed at the user's request. Troll Wall remains available only inside Home through its Feed/Troll Wall selector and posting controls. The Me tab is now named Settings; Profile remains separate.

## Loop branding (2026-10-09)

The user renamed the app to Loop and selected the flat periwinkle circle/chat icon from output/branding/circle-icon-v2.png. Its production icon is the opaque RGB 1024x1024 AppIcon.png in Resources/Assets.xcassets/AppIcon.appiconset. XcodeGen includes Resources, selects AppIcon, and generates CFBundleDisplayName=Loop. The Home title, social alert, authentication labels, sign-out action, and diagnostic export now use Loop. Swift type names, the LiquidGlass target/scheme, artifact filenames, and existing signed bundle IDs remain compatible. The local sign_both.js and ota_server.js scripts also use Loop branding.

## Conversation top edge (2026-10-09)

ChatRoomView attaches the custom chat controls to its ScrollView through iOS 26 safeAreaBar(edge: .top, spacing: 0) and explicitly selects scrollEdgeEffectStyle(.soft, for: .top). Messages pass beneath a system-managed progressive blur/fade; the prior full-width glass rectangle and divider were removed so they do not interfere. Dark themes use the native dark edge, Daylight the light edge. No manual blur, Material, artificial gradient border, or extra darkening layer is added. The header remains a native GlassEffectContainer with 44pt glass controls; dark/light conversation previews are included. Apple controls the exact fade radius/appearance.

## Backend accounts foundation (2026-10-09)

Server/src/auth.ts provides durable password-backed accounts, one-use seven-day invites, 30-day revocable sessions, and private-circle membership. HTTP and WebSocket APIs verify server-issued identities; rooms, presence, signaling, and media are membership-scoped. No insecure invite/session fallback remains on the server. Auth state is ignored by Git and stored atomically under data/auth.json for a single replica. See docs/BackendAccounts.md for the exact API, startup configuration, and limitations. Backend regression tests run with npm test and are included in CI.

The iOS account UI and fake local-session fallback are not yet integrated with the new contract. This foundation has not been deployed to a live backend. Next work is the native signup/login flow, real session validation, authorized media fetching, and then persistent social APIs. Existing legacy room_elena access and public uploads are intentionally denied.

## iOS account integration and PC backend (2026-10-09)

Loop now gates the app behind real invite signup or password login. Stored sessions are server-bound Keychain records, checked with /api/auth/me; legacy mock tokens and expired records are discarded. Signup/login decode JavaScript fractional ISO-8601 timestamps. Username/password and invite fields are sent to the real APIs, with no offline authentication fallback. The HTTP client refuses redirects and public plaintext HTTP; local network HTTP remains available for PC testing.

The Chats screen lists circle group rooms returned by the server instead of demo rooms. Native owner-generated invites, join-by-code, and new-circle actions use the backend. WebSocket identity is token-only, the event stream is registered before connecting, and connection state becomes connected only after authentication. Message history uses the shared date decoder; sign-out clears chat/typing/presence and private downloaded media. Private media downloads use bearer-authenticated same-origin requests and local files for native playback, and upload failures no longer masquerade as successful local uploads. Profile changes now have an authenticated backend endpoint.

The user chose this Windows PC for temporary hosting. Default endpoint is http://192.168.1.132:8080 on the same LAN; Info.plist permits local networking and describes its use, without enabling arbitrary global HTTP loads. Backend HOST configuration allows binding to the LAN address. Server/.env remains private and ignored by Git. Social Home/Stories/Troll data remains mocked until its separate backend phase. Direct messages and account recovery remain future work.

## Stage 3: real social content (2026-10-09)

The installed GlassTabBar now constructs CircleViewModel.production with RemoteFeedRepository. Home selects an authenticated circle, renders empty/live server snapshots, and shares photo posts, 24-hour stories, comments/likes, and anonymous Troll Wall entries. Mock data remains in explicit previews/tests. Private image URLs use the same authenticated cache path as chat media. Settings consent is read from the server rather than written back from an old local preference. Home's creation menu provides private story replies and owner-only Troll Wall report review/removal.

Server/src/social.ts persists content, per-user reactions/seen state, recipient-private replies, and moderation reports. Server/src/socialMedia.ts sanitizes photo bytes via Sharp and registers owned circle-scoped uploads. Auth state supports legacy string media records and new ownership/metadata records without changing existing accounts or passwords. Troll public DTOs never contain author identities; server-only moderation identity and subjects stay in ignored data/social.json. Consent versions keep older tagged posts hidden after opt-out/re-opt-in. Expired story-only media cannot be fetched. See docs/BackendSocial.md for endpoints, guarantees, and limits.


## Interaction and chat fixes (2026-10-10)

Post likes/comments update optimistically with rollback, per-post serialization, and refresh/circle-switch guards. Post detail includes media/description/comments; owner-only caption edit/delete and likers are enforced by new server routes. Home uses a native category picker, a combined glass search/create capsule, and compact timestamps; Story keeps hold/swipe gestures with VoiceOver escape/pause actions.

Chat names follow live room state; member-scoped presence snapshots fix online counts. Any circle member may rename it via the Chats context menu; changes broadcast. Wallpaper moves to the conversation context menu. Private avatars reload on URL changes and use current member profiles; uploads convert HEIC to JPEG. Voice notes now record AAC and privately upload/play/pause/seek, with cancellation/interruption handling.

Calls use pinned WebRTC 154, real mesh SDP/ICE/audio/video tracks, authenticated signaling, and native CallKit instead of fake peers. Both apps must be running for incoming signaling; VoIP push is not implemented. Authenticated /api/calls/ice includes STUN and optional ignored-env TURN_URL/TURN_USERNAME/TURN_PASSWORD; restrictive/cellular NAT still requires a configured TURN relay. Two-device media and native visual QA remain required. Existing PC data, credentials, and public backend tunnel are preserved. CI can use Docker’s official ECR Node image mirror if Docker Hub is unreachable.


Composer follow-up: a native glass photo circle sits beside one message/microphone pill, sized from public tab-bar content height. GlassTabBar now owns the persistent, keyboard-aware composer and coordinated category-bar visibility; ChatRoomView keeps its local dock only for standalone previews. The transition uses an anchored fade/scale handoff, with fade-only Reduce Motion; Apple’s native TabView stays intact.


Search/DM follow-up: Home’s header morphs from the search capsule using native glassEffectID; scrolling or keyboard Done restores it and clears the query. Troll reports are long-press/VoiceOver actions only. Group creation waits for confirmed success, updates circles immediately, and synchronizes live room subscriptions. Private two-person DMs persist in auth.json, appear for the recipient after the first message or an explicit open, and use room-private uploads; only existing circle friends can open them. Chats has no search bar; online friend photos/names open the DM. Existing accounts/content are preserved.

Latest corrected iOS archive is blocked by GitHub Actions billing/spending-limit annotations (run 38008916857); do not distribute the old IPA as this update. Backend tests pass locally. Re-run CI after the user resolves billing, then perform the usual signed-IPA/hash verification.

Refresh follow-up: CircleViewModel treats CancellationError and URLSession cancellation (-999) as normal refresh termination, retains the cached feed, and ignores old-circle failures. Real network/authentication errors still surface. The cancellation classifier has XCTest coverage; remote validation remains blocked until Actions billing is resolved.


Public CI migration: Lemonz0/loop has a new source-only main history; the original Lemonz0/messaging repository remains private. This workspace uses the public repository, with its former Git directory backed up privately under Server/.local/private-repository-history.git. IPA monitoring/download scripts target the new repository. Existing backend data and OTA service are preserved.

Public-source privacy cleanup: signing details and personal paths were removed, the legacy startup secret was replaced with private configuration, and public history was recreated with GitHub no-reply author metadata. Private runtime data and signing files stay local and ignored.

Post-detail layout: a full-screen page now has centered Post/back chrome, author/date, square paged media, SF Symbol like/comment/share controls, author-prefixed caption, glass comment bubbles and a keyboard-aware glass composer. Comment DTOs add public profile data while retaining the original text array for older clients; optimistic comments retain authors. Reply focuses an @mention in the existing flat comment stream. Sharing uses a privately downloaded photo with the native system share sheet. Light/dark previews remain available. GitHub cached access to the removed initial commit still requires a Support purge.
