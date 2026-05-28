# Privacy policy (template)

**EclipsePlex Client** — last updated: May 2026

## Summary

EclipsePlex is a third-party Plex client. It connects to **your** Plex Media Server and Plex.tv only to provide browsing and playback. We do not operate a separate media backend.

## Data we process

| Data | Purpose | Stored where |
|------|---------|--------------|
| Plex sign-in token | Discover servers via Plex.tv | Device Keychain |
| Server access tokens | API calls to your Plex server | Device Keychain |
| Server URLs and library metadata | Browse and play | Device (UserDefaults / app storage) |
| Offline downloads | Playback without network | App sandbox storage |
| Diagnostics export (optional) | Support troubleshooting | User-initiated share only |

We do not sell personal data. Crash reports are sent only if you configure a crash reporting DSN at build time.

## Third parties

- **Plex.tv / your Plex server** — authentication and media metadata
- **VLCKit** — local playback (no cloud upload of media by this library)

## Your choices

- Sign out of Plex.tv in Settings to remove the account token from Keychain.
- Remove servers to delete their tokens.
- Delete offline downloads in Settings.

## Contact

Questions and support: [GitHub Issues](https://github.com/mattbrown64/EclipsePlexClient/issues)

## Changes

We may update this policy; the in-app version string helps identify the build you use.
