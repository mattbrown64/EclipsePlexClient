# Pseudo-TV (QuasiTV-style)

## Overview

Pseudo-TV turns Plex libraries into virtual broadcast channels. Nothing is streamed live from a tuner; the app computes **what should be airing now** from a persisted weekly schedule and starts Plex playback at the correct **offset into the file**.

## Goals (v1)

- Auto-generate channels per server from metadata: network/studio, TV genre, movie genre, decade, library section
- Per-channel content mode: TV-only, movies-only, or mixed (mixed may ship in a follow-up)
- Weekly grid (Monday anchor, local timezone) stored on disk
- Rebuild schedule **after each full cycle** through the channel content pool
- Boost **new / recently added** episodes when rebuilding or patching schedules
- **Pseudo-live** playback: ignore personal resume; use schedule offset only
- Mac + iOS UI: channel list with Now/Next, simplified guide, tune-in to full player

## Architecture

```
Plex API → LibraryIndex → ChannelFactory → WeeklyGridBuilder → ScheduleStore (disk)
                                                      ↓
                                            ProgramResolver(at: Date) → PlaybackRequest
```

## Out of scope (v1)

- Plex Live TV tuners ([LiveTVBrowseView](../EclipsePlexClient/UI/LiveTVBrowseView.swift))
- External PseudoTV/HDHomeRun daemon
- Manual channel editor
- tvOS-first guide (later)

## Implementation phases

1. Engine: models, store, index, grid builder, resolver, tests
2. UI: sidebar entry, channel list, pseudo-live playback
3. Guide + cycle regeneration + Settings rebuild
4. Polish: hidden channels, channel zap, mixed-content channels
