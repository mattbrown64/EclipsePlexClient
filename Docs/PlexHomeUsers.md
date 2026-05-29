# Plex Home user switching

EclipsePlex stores one Plex Media Server token per server. Managed Plex Home users normally require a **per-user token** obtained through Plex PIN / Home user switch APIs (`/api/v2/home/users/{id}`).

## Current behavior

- **Server Management** lists home users (admin read-only).
- **Settings → Plex Home profile** stores a selected user id per server for future token wiring.
- Playback and libraries still use the server’s main token until per-user auth is implemented.

## Next steps for full switching

1. Obtain a managed-user token after PIN approval.
2. Store tokens in Keychain keyed by `serverId + userId`.
3. Pass the active user token on all `PlexMediaServerClient` requests.
4. Invalidate hub/library caches on profile change.

Until then, use **Open Plex home users…** in Server Management for invites and account changes on the web.
