# Message notifications, media and calls

## Signing and notification delivery

Loop requests notification permission after sign-in and exposes system settings in
Settings → Notifications & Sounds. New WebSocket messages produce local alerts,
with message contents hidden. The conversation already on screen receives only a
sound, controlled by the sounds toggle. History loads, own messages and reaction
updates do not generate alerts. Notification taps open the authorized chat.

Free-signed installs can use local alerts while the process receives messages.
iOS suspends the WebSocket in the background; local alerts cannot wake the app.
Background message push requires paid Apple signing and these private server values:

```dotenv
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_KEY_PATH=
APNS_TOPIC=
```

Create an APNs authentication key in the Apple Developer portal and store its .p8
file privately. Enable Push Notifications for the explicit App ID and regenerate
the provisioning profile. Sign Loop with that profile and its `aps-environment`
entitlement (development or production). APNS_TOPIC must match the **final signed
bundle ID**, including any change made by the sideloading tool. The common unsigned
CI IPA remains compatible with free signing; the paid signing step must preserve
the profile's push entitlement. A wildcard profile or merely having a paid account
is insufficient. Loop reads the embedded profile and displays the actual delivery
mode instead of claiming background push is active.

The server accepts device registrations only for its configured topic, binds them
to a session hash, rechecks session expiry and room access on delivery, and removes
registrations on logout or APNs 410. Device tokens are stored in ignored
`Server/data/push-devices.json`. Push payloads contain only a generic alert and
opaque routing IDs; no message text or sender names. Neither credentials nor
device tokens should be committed. Permission/enable/sound changes synchronize on
foreground entry. Server credentials are not configured by default.

## Cloudflare TURN and direct calling

Set these in the ignored `Server/.env` and restart the backend:

```dotenv
CLOUDFLARE_TURN_KEY_ID=
CLOUDFLARE_TURN_API_TOKEN=
```

The authenticated `/api/calls/ice` endpoint generates 24-hour Cloudflare TURN
credentials and refreshes its cache before expiration. The permanent API token
never goes to the phone. Static TURN_URL, TURN_USERNAME and TURN_PASSWORD remain
supported as an alternative. ICE uses `.all`, allowing host and STUN connections
to take priority over relayed media. Configuring TURN does not force relay-only
calls. A Cloudflare outage falls back to direct/STUN candidates. Some cellular,
carrier NAT and restricted Wi-Fi networks cannot connect directly.

CallKit now fulfills outgoing start actions and configures audio before the system
activates it. Incoming calls still require both apps to be running: **PushKit/VoIP
push is not implemented by message APNs support**. Validate microphone/camera,
incoming/outgoing audio, speaker, hangup, same-Wi-Fi and Wi-Fi-to-cellular media on
two devices. CI compilation cannot certify real network connectivity.

## Media and compact layout checks

Photo intake selects image representations first (including Live Photos), encodes
real JPEG bytes with a .jpg filename, captures the destination room explicitly,
and uses the signed-in server. Photos retain dimensions and render in a bounded
image card while authenticated downloads load. Upload errors display server errors.
The source .dat file is discarded after conversion.

Story circles use a consistent 70-point slot and 76-point cell, including the add
button. Labels stay on one line; ring geometry is independent of available screen
width. Check the native layout on iPhone 12 (390 points), 13 Pro Max (428 points),
and 16 Pro Max (440 points), plus Dynamic Type, all three themes and Reduce Motion.
These device checks remain necessary after installing the CI artifact.

References: [Cloudflare credentials](https://developers.cloudflare.com/realtime/turn/generate-credentials/),
[Apple APNs setup](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns),
[Apple CallKit](https://developer.apple.com/documentation/callkit/making-and-receiving-voip-calls).
