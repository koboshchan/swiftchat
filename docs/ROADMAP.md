# Roadmap

## Completed foundation

- Workspace, modular packages, run loop, repository protections, models, mock provider, GRDB cache, Keychain store, Gateway codec, native UI shell, messaging interactions, onboarding, settings, media and plugin contracts, and tests.

## Next: authenticated read-only connector

- Implement and fixture-test the Discord REST DTO layer and rate-limit scheduler.
- Implement the Gateway session actor with heartbeat, resume, invalid-session, backoff, and zlib-stream framing.
- Expand the implemented session bootstrap/current-user validation with logout, expiry recovery, and account switching.
- Implement the sanitized protocol release gate described in `PROTOCOL_BASELINE.md`; do not claim ban-safe parity.
- Replace the mock provider through configuration while retaining the same `ChatProvider` contract.

## Then

- Multipart upload streaming and richer embeds/stickers/GIF search.
- Threads, forums, search, pins, moderation, notifications, and presence.
- WebRTC/libdave voice and video behind a `VoiceEngine` interface.
- Sandboxed WASI execution, XPC broker, declarative plugin UI, audit log, and permission dashboard.
