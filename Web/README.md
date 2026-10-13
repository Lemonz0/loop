# Loop for desktop

A standalone, responsive HTML/CSS/JavaScript prototype of Loop. No application backend, accounts, WebSocket connections, or runtime third-party requests. The iOS app and server are unchanged.

## Open locally

With Node.js installed, run `npm start` from `Web`, then open http://127.0.0.1:4173. No dependency installation or build step is required. `dist/index.html` can also be served by any static web host.

## Included

- Desktop feed, circle panel, stories, and anonymous Troll Wall
- Create text/photo posts, comments, likes, saved moments, and local 24-hour stories
- Demo conversations with locally saved messages; no simulated delivery or live accounts
- Search people and posts; rename the demo circle
- Editable profile; Aurora, Onyx, and Daylight themes
- Local notification preferences and optional message tone
- Responsive navigation, keyboard-accessible dialogs, reduced-motion support

Browser localStorage stores demo content under `loop-desktop-demo-v1`. Reset it in Settings. Photos are resized client-side; storage capacity depends on the browser. Troll Wall records have no author field. These are UI demonstrations, not privacy or authentication guarantees.

## Checks

Run `npm run check` for JavaScript syntax validation. The desktop workflow also checks HTML/CSS/JavaScript delimiter balance and local asset references.

## Assets

The app icon is copied from Loop’s existing AppIcon. Sample landscape and portrait photographs are bundled locally from Unsplash’s image CDN. See `assets.json` for source URLs. They are fictional demo content, not real circle members or account data. The supplied phone screenshots were used as visual references, not republished.
