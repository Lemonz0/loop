# Loop social backend

Live social content is scoped to the selected circle. Every route requires a server-issued bearer session and current circle membership. The installed app uses RemoteFeedRepository; MockFeedRepository remains for previews/tests only. Home has a circle selector and starts empty rather than showing invented friends/posts.

Base: `/api/circles/:circleId/social`

| Method | Suffix | Behavior |
|---|---|---|
| GET | empty | `{friends, posts, stories, trollPosts}` for this circle and requesting user |
| POST | `/media` | Raw photo bytes; 20 MB limit, two concurrent processors, 40M input pixels; returns sanitized JPEG URL |
| POST | `/posts`, `/stories` | `{imageURL, caption}` from this user's sanitized upload in this circle |
| POST | `/trolls` | `{imageURL, caption, subjectIDs}`; consent is checked for every declared subject |
| POST | `/posts/:id/like` | Toggle this account's like |
| POST | `/posts/:id/comments` | `{text}`; persist comment |
| POST | `/stories/:id/seen`, `/like` | Seen/like state; reject expired stories |
| POST | `/stories/:id/replies` | `{text}`; private reply to story owner |
| GET | `/stories/:id/replies`, `/replies` | Recipient-only replies/inbox; other members cannot read them |
| POST | `/trolls/:id/react` | Toggle this account's laugh |
| POST | `/trolls/:id/report` | `{reason}`; hide for reporter and persist moderation report |
| GET | `/reports` | Circle-owner-only reports, without uploader identity |
| POST | `/trolls/:id/remove` | Circle owner hides reported post for the whole circle |

`POST /api/social/consent` accepts `{allowed: Bool}` for the authenticated account only; a supplied user ID cannot change someone else's preference.

Photo handling re-encodes images through Sharp, applies orientation, resizes to at most 2048 pixels, and strips EXIF/XMP/ICC metadata. SVG/PDF/active formats are rejected. The native picker also prepares a bounded JPEG so HEIC photos are supported. No client-authored URL, user ID, reaction count, timestamp, or expiry is trusted as authority. Only owned sanitized uploads can create social content.

Troll Wall's public payload has no author, uploader, subject list, or moderation identity. A separate anonymous image URL prevents correlation with an identified post/avatar URL; anonymous image copies cannot be repurposed as an identified post/profile photo. Moderation authorship exists only in the private server-side `data/social.json`. Faces, captions, and intentionally shared content can still identify people; this is not a promise of cryptographic anonymity against image-content analysis. Consent enforcement checks declared pictured subjects, not automated face recognition.

Opting out hides existing tagged Troll posts. Consent-version checks keep those posts hidden even after the user opts back in. This setting is server-authoritative; refreshing the app never resets it from a stale local toggle. Reports and owner removals persist across restarts.

Stories stop appearing after 24 hours and expired story-only media downloads are denied, as are new likes/seen/reply writes. A separately published regular post can legitimately keep the same media accessible. Private text replies remain in the recipient's inbox after story expiry. Already downloaded copies/screenshots cannot be recalled. Expired records/files remain in private storage for now; retention/purging is future work.

Storage remains atomic JSON for one server process on the user's PC. Keep `data/auth.json`, `data/social.json`, and `uploads/` private and out of Git; mount persistent volumes for future hosting. Multi-replica databases, push notifications, content deletion UI, and background event subscriptions remain later stages. Pull-to-refresh fetches authoritative content now.
