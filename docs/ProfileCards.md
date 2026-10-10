# Loop profile cards

Assumptions:
- Loop remains a closed-circle app. Profiles resolve only for a shared circle, an existing private conversation, or the signed-in user. No public user directory is introduced.
- Existing group owners retain moderation permissions. An Admin badge is a group role; owners control promotion, restriction, and removal. Historical membership dates/added-by values are omitted if never recorded, rather than invented.
- Notes, nicknames, contacts, mute, clear-chat position, and contact requests belong to the viewer. Disappearing messages use the shorter nonzero duration set by either participant.
- The existing Profile tab remains the account editor. Bot, official, verified, and deactivated flags are server-managed and cannot be self-awarded in the editor.

`UserProfileSheet` is the only full profile card. `profileEntry` adds identity tapping, accessible opening, a native zoom transition source, and a long-press quick peek. `ProfilePresentation` rejects overlapping requests across hosts. Each presented screen provides a `profilePresentationHost`; the main tab host retains navigation state. Message/call navigation waits for card dismissal. Opening a chat from the call screen minimizes its overlay without disconnecting the call; a glass return-to-call control restores it. Root theme injection and regular native glass govern all surfaces; accessibility contrast/transparency preferences add native glass tint.

Entry points:
- Incoming chat avatars, group sender names, direct chat headers and direct chat-list identity labels.
- Group header opens searchable members. Chats menu exposes searchable contacts and call history.
- Verified `@username` tokens inside message text resolve against authenticated circle members; unknown tokens remain plain text. Display-name guessing is never used.
- Message context menu offers Reply and five reactions. Reply headers and reaction people open the same card. Mentions and reactions deliberately omit chat-specific settings.
- Social post/story authors, comment authors, private-reply senders, and existing post-liker lists.
- Call participant avatars/names and persisted call history participants.

Authenticated APIs: `/api/profiles/:id`, `/api/profiles/:id/actions`, `/api/profiles/:id/group`, `/api/profiles/settings`, `/api/profiles/requests`, `/api/calls/history`, and `/api/chats/:room/messages/:message/reaction`. Cards include authorized shared items, mutual groups/contacts, server-filtered presence and optional local time. Server-owned replies/reactions never accept client-authored identity fields.

`profiles.json` contains private relationship data and moderation reports. `calls.json` contains private call events. Both are ignored alongside existing account/chat/social files. Atomic profile writes preserve data on failure. The client cache is memory-only, session-scoped, cleared at logout, and invalidated by account updates. Offline cards retain cached information; authorization failures discard the visible card. Cached images use the existing same-origin bearer media loader.

Blocking and private-profile consent gate direct-room creation and message/typing/call signaling. Group restriction gates messaging, calling, and social writes; removal revokes already-joined sockets. Presence is filtered on the server and redacted after privacy changes. Clear chat affects only the viewer. Disappearing history and referenced media are filtered on reads, and shared-media payloads obey the same authorization.

Validation: backend regression and profile integration tests; hostless `ProfileCodecTests` alongside theme tests; delimiter balance and palette contrast checks; remote Xcode 26 archive/IPA build. Manual iOS checks remain necessary for all three themes, actual glass rendering, text over wallpapers, Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, avatar pinch/pan, native sheet dragging and outside dismissal, and navigation/call transitions. Windows cannot certify rendered iOS glass.

Operational notes: restart/deploy the backend to expose the new endpoints. Existing accounts and private data need no reset. Old group-member metadata remains optional. Existing call history starts recording after this version; it represents call signaling events, not measured call durations. Loop currently has no remote push-notification service; mute persists notification preference without affecting call audio controls. Profile reports persist privately for operator review in the server store.
