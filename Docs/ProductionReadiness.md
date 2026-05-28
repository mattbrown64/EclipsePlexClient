# Production readiness tracker

Living checklist for EclipsePlex release gates.

## Release gates

| Gate | Criteria | Status |
|------|----------|--------|
| Security | Plex tokens in Keychain; logs redacted; network policy enforced | Done |
| Test | macOS + iOS + tvOS CI; security regression tests | Done |
| Privacy / legal | Privacy manifest; in-app licenses; policy/support URLs documented | Done |
| Crash-free beta | Crash reporter wired; diagnostics export sanitized | Done |

## Acceptance checklist (definition of done)

- [x] Secrets in Keychain; legacy UserDefaults keys removed after migration
- [x] Version/build from Bundle; Plex headers use same source
- [x] iOS 26 / tvOS 17 / macOS 14 targets aligned in project, Podfile, CI
- [x] `PrivacyInfo.xcprivacy` present and accurate
- [x] In-app Licenses + privacy/support links in Settings
- [x] Crash reporter active (local buffer + optional `SentryDSN` in Info.plist)
- [x] CI: macOS unit, iOS unit, iOS UI, tvOS build, deployment drift check
- [x] Keychain + redaction + ATS policy tests
- [x] ContentView / PlexMediaServerAPI split into focused modules
- [x] Offline persistence errors surfaced; iOS background download session
- [x] Release checklist doc complete

## Sign-off (manual, pre–App Store)

- [ ] Apple Developer Program enrollment and signing (manual, near release)
- [ ] TestFlight external beta
- [ ] App Store metadata and screenshots

## Key implementation references

| Area | Location |
|------|----------|
| Keychain | `EclipsePlexClient/Security/KeychainStore.swift` |
| Logging | `EclipsePlexClient/Security/AppLog.swift` |
| Network policy | `EclipsePlexClient/Security/PlexNetworkPolicy.swift` |
| Version | `EclipsePlexClient/Support/AppVersion.swift` |
| Privacy manifest | `Support/PrivacyInfo.xcprivacy` |
| Licenses UI | `EclipsePlexClient/UI/LicensesView.swift` |
| Diagnostics | `EclipsePlexClient/Support/AppDiagnostics.swift` |
| Crash buffer | `EclipsePlexClient/Support/CrashReporter.swift` |
| CI | `.github/workflows/ci.yml`, `scripts/check-deployment-targets.sh` |
