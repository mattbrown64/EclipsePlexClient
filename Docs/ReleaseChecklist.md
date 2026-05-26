# Release checklist

Use before each TestFlight or App Store submission.

## Build

- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode
- [ ] Verify About screen and Plex client headers show correct version
- [ ] Archive Release configuration for each platform (iOS, macOS, tvOS)
- [ ] Upload dSYMs to crash reporter (if DSN configured)

## App Store Connect

- [ ] Privacy policy URL live
- [ ] Support URL live
- [ ] App Privacy answers match `PrivacyInfo.xcprivacy`
- [ ] Export compliance (encryption) answered
- [ ] Screenshots per device class
- [ ] Review notes: third-party Plex client; PIN sign-in in browser; local network

## Legal

- [ ] In-app Licenses screen includes VLCKit / VLCUI / LGPL text
- [ ] No implication of official Plex affiliation in marketing copy

## QA smoke

- [ ] PIN sign-in and server discovery
- [ ] LAN server manual add (HTTP)
- [ ] Playback direct and transcode
- [ ] Offline download start, background resume (iOS), playback offline
- [ ] Sign out clears account token from Keychain
- [ ] Export diagnostics contains no secrets

## Signing (manual)

- [ ] Apple Developer Program active
- [ ] Provisioning profiles and certificates valid per platform
