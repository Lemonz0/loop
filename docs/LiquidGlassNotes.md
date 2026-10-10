# Apple iOS 26 Liquid Glass SDK Reference & Implementation Notes

## Overview
This document specifies the official Apple Liquid Glass APIs for iOS 26 (Xcode 26 SDK), their exact signatures, availability, integration rules, and implementation in the `LiquidGlassMessaging` codebase.

---

## 1. Core Liquid Glass Modifiers

### `.glassEffect(_:in:)`
- **Availability:** iOS 26.0+, macOS 26.0+, visionOS 26.0+
- **Apple Documentation:** [Applying Liquid Glass to Custom Views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- **Signature:**
  ```swift
  func glassEffect(_ glass: Glass = .regular, in shape: some Shape = Capsule()) -> some View
  ```
- **Variants of `Glass`:**
  - `Glass.regular`: Standard translucent glass with optical refraction of background content.
  - `Glass.clear`: Ultra-minimal glass with specular edge refraction.
  - `glass.tint(_ color: Color)`: Colorizes the glass refraction body while preserving specular edge highlights.
  - `glass.interactive()`: Enables touch-down depression, specular gleam, and haptic spring response.
- **Rules:**
  - Use `.glassEffect` only on custom surfaces (e.g. Profile card, status pills, floating badges). Standard system controls (Navigation bars, Tab bars, Menus) receive Liquid Glass automatically.
  - Never stack glass directly on glass without enclosing in a `GlassEffectContainer`.

---

## 2. Containers & Morphing

### `GlassEffectContainer`
- **Availability:** iOS 26.0+
- **Apple Documentation:** [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- **Signature:**
  ```swift
  struct GlassEffectContainer<Content: View>: View {
      init(spacing: CGFloat = 8.0, @ViewBuilder content: () -> Content)
  }
  ```
- **Purpose:** Groups adjacent glass elements into a unified optical refraction context to prevent internal occlusion and refractive interference.

### `.glassEffectID(_:in:)` & `.glassEffectUnion(id:in:)`
- **Signature:**
  ```swift
  func glassEffectID(_ id: some Hashable, in namespace: Namespace.ID) -> some View
  func glassEffectUnion(id: some Hashable, in namespace: Namespace.ID) -> some View
  ```
- **Purpose:** Associates an identity with a glass element across views for fluid shape morphing during layout transitions.

---

## 3. Button Styles

### `.buttonStyle(.glass)` & `.buttonStyle(.glassProminent)`
- **Availability:** iOS 26.0+
- **Apple Documentation:** [Human Interface Guidelines - Buttons (Liquid Glass)](https://developer.apple.com/design/human-interface-guidelines/buttons)
- **Signatures:**
  ```swift
  extension ButtonStyle where Self == GlassButtonStyle {
      static var glass: GlassButtonStyle { get }
  }
  extension ButtonStyle where Self == GlassProminentButtonStyle {
      static var glassProminent: GlassProminentButtonStyle { get }
  }
  ```
- **Usage:**
  - Secondary buttons: `.buttonStyle(.glass)`
  - Primary / Call-to-action buttons: `.buttonStyle(.glassProminent).tint(Color.blue)`
  - Destructive buttons: `Button(role: .destructive)`

---

## 4. Navigation & Layout

### `NavigationStack` & Toolbar
- Navigation bars in iOS 26 automatically adopt Liquid Glass chrome.
- Large titles: `.navigationTitle("Settings")` with `.navigationBarTitleDisplayMode(.large)`.
- Split toolbar button groups with `ToolbarSpacer()`.

### GlassEffectContainer vs Grouped Lists
- Standard SwiftUI `List` / `Form` groupings collapse adjacent rows into a single continuous platter with zero vertical gap, causing row glass backgrounds to touch and stack directly on top of each other.
- To achieve spacious, luxurious Liquid Glass aesthetics, use `ScrollView` with `VStack(spacing: 14...16)` wrapped in `GlassEffectContainer(spacing: 14)`.
- Each card receives `.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))` with independent content shape and padding.
- The 14-16pt gaps between cards allow the rich `MeshGradient` background to pass between elements, highlighting the specular edge refraction around the continuous corner curves.
- Fixed bottom tab bar: Do not apply `.tabBarMinimizeBehavior(.onScrollDown)` if a persistent bottom bar is desired, as this modifier collapses the entire bar into a single floating circular button in the bottom corner on scroll.

---

## 5. Pure OLED Black Background & Refraction
- **True #000000 Architecture:** Configured via `ThemeManager.shared.isPureOLEDBlack` with user controls in Settings -> Appearance & Theme ("Pure OLED Black (Whole App)" and "Onyx (Pure OLED Black)").
- **Optical Physics on OLED:** True black disables emissive sub-pixels on Super Retina XDR OLED displays, eliminating backlight bleed and providing maximum optical dynamic range for Apple Liquid Glass specular highlights and rim refraction.
- **Unified Screens:** All root views (Settings, Home, Messages, Chat Room, Calls, Diagnostics) and sheet modals utilize `Color.black.ignoresSafeArea()` as their foundational background layer.

---

## 6. ProMotion Frame Pacing (Hidden Service)

- **CADisableMinimumFrameDurationOnPhone:** Configured in `project.yml` as `YES`.
- **`ProMotionManager`:** Non-UI singleton managing `CADisplayLink` with `CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)` during user interactions and gestures, falling back to 80Hz and 10Hz when idle.
- Zero UI controls or FPS badges exposed to the user.
