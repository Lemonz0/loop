# Spotify profiles and listening activity

Every Loop user can optionally connect Spotify from **Profile → Edit profile details & privacy**. Spotify name/profile link appears on the shared profile card after connection. Listening activity starts **off**; the separate sharing toggle enables it only for **mutual contacts**, as requested. Blocking, unavailable/deactivated profiles, circle/DM access, and profile privacy are enforced by the backend before returning data and again after upstream requests finish.

DM headers display the current song and artist while a permitted, fresh activity payload exists. Otherwise they retain the normal conversation status. The Spotify profile section shows the same payload with album, uncropped artwork, progress, and a link to the track. Official monochrome Spotify logo assets adapt to the active light/dark theme; glass remains native iOS 26 regular glass.

## Server configuration

Set these only in the private `Server/.env` or the deployment's secret environment:

```text
SPOTIFY_CLIENT_ID=<public developer app client ID>
SPOTIFY_REDIRECT_URI=https://<backend-host>/api/spotify/callback
SPOTIFY_TOKEN_KEY=<64 hexadecimal characters, generated securely once>
```

Register the exact redirect URI in the Spotify dashboard and select Web API. The PC test installation uses its existing Cloudflare backend HTTPS hostname. If that temporary hostname changes, update both the dashboard URI and `SPOTIFY_REDIRECT_URI`, then restart the backend. Retain the encryption key: changing it makes saved connections unreadable, and startup deliberately fails rather than replacing them.

Users must be allowed to authenticate with the Spotify developer app. Development mode requires the developer account's Premium subscription and currently permits five allowlisted users. Add testers through Spotify's dashboard. No client secret, Spotify password, email access, or playback-control permission is required.

## OAuth and credentials

`POST /api/spotify/connect` starts server-held Authorization Code + PKCE with random state bound to the authenticated Loop session. The HTTPS callback exchanges the code on the server and reads the connected user's identity. It then returns only an outcome and attempt identifier to the native `ASWebAuthenticationSession` through `loop-spotify://callback`. Unknown, expired, replayed, logged-out, or canceled attempts cannot finish linking. A Spotify identity cannot be linked to two Loop accounts. Sharing is preserved only when reconnecting the same Spotify identity; a different identity starts private.

Scopes: `user-read-private` for profile/subscription access and `user-read-playback-state` for current playback plus its private-session flag. Spotify tokens never enter the app, profile payloads, URL callbacks, analytics, or public Git history. Access and refresh tokens are encrypted with AES-256-GCM in the ignored `Server/data/spotify.json`; refresh-token rotation is persisted atomically.

Authenticated endpoints:
- `GET /api/spotify/settings`
- `POST /api/spotify/connect`, `/cancel`, `/disconnect`, `/sharing`
- `GET /api/spotify/users/:userId`

The only public integration endpoint is `GET /api/spotify/callback`, which validates the pending OAuth state. Authentication errors do not disclose provider credentials. Native completion validates its attempt and the current Loop session before reporting success.

## Activity freshness and quotas

Profiles and DM headers poll only while visible in an active app scene, every 20 seconds. The server shares a 20-second cache and deduplicates concurrent requests per listener; there is no continuously running background polling loop. A friend can see playback from another device while the listener's Loop app is closed, provided the backend is running and the friend has an active view.

Song payloads expire after at most 35 seconds or the remaining track duration, whichever is shorter. The UI hides expired activity even if a request fails. Paused playback, ads, local-only tracks, podcasts, Spotify private sessions, missing privacy flags, 204 responses, provider errors, and revoked access produce no activity. Rate limits suppress activity and respect Retry-After using a shared cooldown. Provider authorization failures expose a reconnect control to the account owner. No listening history is persisted.

## Validation and remaining live check

Backend tests mock the Spotify service and cover PKCE, replay/expiry, logout/cancel races, encrypted persistence, refresh rotation, mutual contacts, blocking/private profiles, stale/paused/private playback, concurrent request deduplication, rate limits, disconnect, and HTTP authorization. Hostless `SpotifyCodecTests` cover optional redacted payloads, JavaScript timestamp decoding, expiry, and progress clamping. CI builds the iOS OAuth flow and native glass UI.

After installing the updated IPA, connect a real Spotify account through the native consent screen, play a song, enable sharing, and verify it from a second mutually added account. Also check pausing, Spotify Private Session, removing a contact, blocking, sharing-off, disconnect, app backgrounding, and all three Loop themes. Mocked tests cannot certify real Spotify access or rendered iOS behavior.

References: [PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), [playback state](https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback), [redirect requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri), [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes), [branding and official logo source](https://developer.spotify.com/documentation/design).
