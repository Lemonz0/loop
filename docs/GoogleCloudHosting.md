# Google Cloud hosting for Loop

Loop uses one Node.js process with JSON account/chat stores and local media.
Deploy one Compute Engine VM with persistent disk; do not run multiple backend
replicas against these files. A small Ubuntu 24.04 VM in a European region is
the initial deployment target. Measure usage before increasing capacity.

## Layout

- `/opt/loop/source`: source-only checkout of Lemonz0/loop.
- `/opt/loop/compose.yml` and `Caddyfile`: backend and HTTPS reverse proxy.
- `/srv/loop/data` and `/srv/loop/uploads`: existing private data, mounted into
  the backend separately to preserve its current on-disk layout.
- `/srv/loop/.env`: private backend credentials; never put this in metadata,
  the container build context, GitHub, or the app bundle.
- `/srv/loop/hosting.env`: `LOOP_HOST=<public DNS hostname>` for Caddy.
- `/srv/loop/caddy-data`: persistent TLS certificates.

Only TCP ports 80/443 are publicly exposed. The backend's port 8080 is internal
to Docker. Administrative SSH uses an IAP tunnel with the firewall restricted
to Google's IAP range, rather than opening SSH to the internet.

## Migration and verification

1. Authenticate the Google Cloud CLI using the account with the credits.
2. Create a dedicated Loop project and attach the intended billing account.
   Inspect credit expiry and the VM cost estimate. Add budget notifications;
   notifications are not a spending cap.
3. Reserve a regional IP. Create the VM with Ubuntu 24.04 and
   `Server/deploy/gcp/startup.sh` as its startup script. Retain the persistent
   disk independently of VM deletion, and configure disk snapshot backups.
4. Wait for setup to finish. Transfer a consistent copy of the existing
   `Server/data`, `Server/uploads`, and private `Server/.env` over authenticated
   SSH. Stop writes briefly for the final copy; preserve the original PC data.
   Do not package `Server/.local` or its private repository history.
5. Give the two runtime directories to UID/GID 1000 and restrict `.env` to root.
   Adjust any APNs key path to its transferred private key on the VM. Preserve
   the Spotify encryption key; update its registered redirect URI if needed.
6. Point a public DNS hostname at the reserved IP and write `LOOP_HOST` into
   `/srv/loop/hosting.env`. Start with `docker compose up -d --build` from
   `/opt/loop`. Caddy obtains and renews trusted HTTPS certificates.
7. Verify HTTPS `/health`, rejection of unauthenticated API and WebSocket
   requests, existing-account login, authenticated chat/media, and persistence
   across a container restart. Restore a backup before relying on it.
8. Update the iOS server address to the verified HTTPS URL. Saved sessions are
   server-bound, so users may need to sign in again. Test two-device messaging
   and calls over separate networks. Calling across restrictive networks still
   needs a configured TURN relay; APNs/Spotify require their own valid setup.

Hosting preparation alone does not mean a VM or public endpoint is deployed.
Record the actual project, endpoint, migration verification, and backup state
in ignored local deployment notes after completing these steps.

References: [Compute Engine](https://cloud.google.com/products/compute),
[Linux startup scripts](https://docs.cloud.google.com/compute/docs/instances/startup-scripts/linux),
[Google Cloud trial terms](https://docs.cloud.google.com/free/docs/free-cloud-features).
