# Server management

EclipsePlex exposes Plex Media Server admin features from **Settings → Server management** (owned or admin-capable servers).

## Permissions

- **Sessions:** Any token that can read `/status/sessions` sees active streams. Stopping a stream requires server ownership (or equivalent admin).
- **Libraries:** Scan, refresh metadata, analyze, empty trash, rename, and remove sections require library admin rights (owned server or successful sessions probe).
- **Metadata tools:** Edit, fix match, refresh, optimize, and delete on movie/show/episode detail screens use the same library admin gate.

Capabilities are probed when you open server management or a catalog with admin-eligible items. Shared servers may show read-only sessions until the probe completes.

## Notifications (offline downloads)

Settings → **Downloads** toggles success/failure local notifications when background downloads finish.

## Last online

When a server is unreachable, the sidebar shows **Last online** based on the last successful connection probe.

## Fix match search options

Fix match supports title, year, TV show/season labels, and external IDs (`imdb-`, `tmdb-`, `tvdb-` prefixes) passed to Plex’s match API.

## Diagnostics

Admin actions are logged under the **Network** category in app logs. Export diagnostics from Settings to include server reachability, last-online timestamps, and admin capability flags per server.

## Plex web for advanced admin

Invite/remove users, fine-grained library sharing, DVR, and creating new library sections with folders are not fully duplicated here—use [Plex home users](https://app.plex.tv/desktop#!/settings/plex/home) for those workflows.
