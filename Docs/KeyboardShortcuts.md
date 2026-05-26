# Keyboard shortcuts

## Browse (macOS)

| Key | Action |
|-----|--------|
| ⌘⇧B | Open browse sidebar / sheet |
| ⌘F | Search current Plex server |
| ⌘R | Refresh libraries for current server |
| ↑ / ↓ | Move focus in sidebar, home hubs, or catalog |
| ← / → | Home hubs / catalog grid; from sidebar → detail |
| Tab | Switch focus between sidebar and detail |
| Return | Activate selected row (open item) |
| E | Back one level (navigation stack or sidebar) |
| W | Watch (media detail) |
| R | Resume (media detail, when available) |

## Playback (macOS)

| Key | Action |
|-----|--------|
| Space | Play / pause |
| Esc | Exit player |
| N | Next episode |
| P | Previous episode |
| , | Back 10 seconds |
| . | Forward 10 seconds |

## iPad / iPhone (hardware keyboard)

Same as macOS browse and playback keys where the view has focus. Use the **Browse** toolbar button when the sidebar is hidden.

## Apple TV (Siri Remote)

| Control | Action |
|---------|--------|
| Swipe | Move focus (sidebar, home shelves, catalog grid) |
| Select | Open item / play |
| Menu | Back one screen / exit player |
| Browse toolbar | Open sources & libraries sheet |

Focus regions: `sidebar`, `homeHubs`, `catalog`, `detailActions` (Watch / Resume on media detail).

Build tvOS with `./scripts/fetch-tvvlckit.sh` and the **Apple TV Simulator** destination in `EclipsePlexClient.xcworkspace`.
