# Deferred features

Items scoped but not yet shipped on `main`, or explicitly deferred until a dedicated effort lands.

## QOL roadmap (Phase 6)

| Feature | Notes |
|---------|--------|
| **Trakt integration** | New third-party OAuth and sync layer |
| **Universal / cross-server search** | Beyond per-server search |
| **Handoff / Continuity** | `NSUserActivity` + playback state (Mac ↔ iOS) |
| **macOS Picture in Picture** | Blocked on VLC surface; revisit with native HLS/AVPlayer path |
| **Server-side catalog sort** | `PlexSectionSortQuery` exists but client-side sort already persists per library |

## Pseudo-TV (QuasiTV-style)

Client-side virtual channels from Plex libraries: auto-generated channels (network, genre, decade, library section), **weekly repeating grid** persisted on disk, **schedule rebuild after each content cycle** with **new-episode priority**, **pseudo-live** tune-in at the schedule offset (no personal resume).

| Platform (v1) | Mac + iOS |
| Playback | Schedule offset only |
| Not in scope v1 | Plex DVR/tuner integration, M3U/HDHomeRun, web admin UI, tvOS guide |

**Spec:** [PseudoTV.md](PseudoTV.md)

**Branch:** `feat/pseudo-tv` (v1 engine + channel list UI in progress)

Track interest in GitHub issues before expanding scope (manual channels, mixed-content polish, in-player channel zap, full 24h guide).
