# Post viewing

Posts now open from feed photos, captions, or the comments action in a native bottom sheet rather than a full-screen cover. `FloatingGlassSheet` shares the profile viewer's medium/large detents, 40pt corners, drag indicator, and outside-tap dismissal. Native iOS 26 supplies the partial-height glass and its full-height adaptation. The decorative ambient background uses the same subtle layer as the profile viewer so it does not replace the sheet's glass.

Post content scrolls with 14pt spacing between surfaces. The pinned header has a close control, and the comment composer stays at the bottom above the keyboard. Focusing the composer or replying expands the sheet; the comment action scrolls to comments with a Reduce Motion-safe transition. Opening provides the existing light haptic.

Author and comment names/avatars still open the shared profile card from the post sheet. Likes, replies, and sharing retain their existing authorization. Photos retain their separate full-screen viewer. These nested presentations remain independent of the post's native drag-to-dismiss gesture.

Validation: delimiter checks, remote Xcode archive and existing CI tests. On-device checks should cover opening each entry point, medium-size scrolling, expanding/collapsing/dismissing, keyboard and reply behavior, nested profiles/likes/photos/sharing, and Onyx/Aurora/Daylight with accessibility settings.
