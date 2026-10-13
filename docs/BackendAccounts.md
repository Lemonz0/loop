# Loop account and private-circle backend

Start with Node.js 22: `npm ci`, `npm test`, `npm run build`, then `npm start` from `Server/`.

On first startup, set `INVITE_KEY` to a cryptographically random secret of 24-256 characters. `.env.example` is a template; the server reads process environment variables, not `.env` files automatically. Redeem this one-use bootstrap invite within seven days to create the first circle owner. The owner can generate further one-use invites. No default invite or eight-character bypass exists.

## HTTP contract

JSON request bodies are limited to 16 KiB. Auth attempts are limited to 10 per socket peer IP per minute, plus a global bound of eight pending password derivations. Reverse proxies need their own per-client rate limits; forwarded IP headers are deliberately not trusted. Use HTTPS/WSS outside localhost.

| Method | Route | Body / behavior |
|---|---|---|
| GET | `/health` | Public readiness check |
| POST | `/api/auth/invite` | `{secretKey, username, chosenDisplayName, password}`; creates account and returns `{success, session}` |
| POST | `/api/auth/login` | `{username, password}`; returns the same session shape |
| GET | `/api/auth/me` | Returns authenticated profile and circles |
| POST | `/api/auth/logout` | Revokes this session token |
| GET | `/api/circles` | Only circles containing the authenticated user |
| POST | `/api/circles` | `{name}`; creates a private circle and its group room |
| POST | `/api/circles/:id/invites` | Circle-owner only; returns `{code, circleId, expiresAt}` |
| POST | `/api/invites/join` | `{secretKey}`; existing account joins invited circle |
| POST | `/api/media/upload` | Bearer auth required; optional `X-Circle-ID`, `X-File-Name`; returns a relative file URL |
| GET | `/uploads/:file` | Bearer auth plus membership in the file's circle required |

All routes except health, signup, and login require `Authorization: Bearer <token>`. Registration passwords require 12-128 characters without leading/trailing whitespace; usernames use 3-32 ASCII letters, digits, or underscores and are case-insensitive. Duplicate usernames return 409. Errors use `{success:false,errorMessage}` and appropriate 400/401/403/404/409/413/429 statuses.

## WebSocket contract

Connect `/ws`, then send `{type:"auth",token}` within ten seconds. Client-supplied `user` fields are ignored. Only a genuine unexpired persisted session authenticates. Group room IDs come from authorized circle membership; arbitrary room joins, history reads, messaging, typing, signaling, and theme changes are rejected. Message/signaling identity, room ID, and timestamps are server-owned. Revoked/expired recipients are excluded from broadcasts. Presence stays within shared circles. Each new circle gets a fresh random group-room ID; legacy room_main history is not automatically granted to newly created accounts. Direct-message room creation and member administration are future work; the old hard-coded `room_elena` is not an authorized private room.

## Storage and deployment

`data/auth.json` uses atomic replace and stores salted scrypt password hashes (N=65536, r=8, p=2), SHA-256 token/invite hashes, circle membership, and media ownership. Invite redemption checks are repeated inside the synchronous commit to prevent concurrent double use. Sessions last 30 days; invites seven days and one use. Password parameters follow [OWASP's scrypt guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).

Mount persistent `/app/data` and `/app/uploads` volumes when running the Docker image. Run **one server process/replica**: this JSON storage is a foundation for the private prototype, not a distributed database. Back up the private data directory securely. Corrupt state is not silently overwritten. Existing uploads without ownership records are not publicly accessible.

## Client integration

The native app now implements invite signup, password login, server-bound Keychain session validation, logout, owner-created circle invites, joining circles, and real circle chat rooms/history. It rejects former fake tokens and contains no offline sign-in bypass. Authenticated same-origin media downloads are played from private local cache files, cleared on logout. POST /api/auth/profile persists display name and authorized avatar changes. Home/Stories/Troll Wall still use the mock FeedRepository.

Loop now defaults to the HTTPS Google Cloud backend. The former PC default is migrated automatically; custom endpoints remain configurable. Sessions remain server-bound, so users switching from the PC address must sign in again with their existing accounts. See [Google Cloud hosting](GoogleCloudHosting.md) for deployment and migration details. For explicit local development, set HOST and PORT in the ignored Server/.env, then use npm run start:local after building.
