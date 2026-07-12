# Discord production protocol baseline

Observed on 11 July 2026 from Discord's own production bootstrap and the locally installed desktop bundle. No account token, cookie, message body, authorization header, or personal payload was recorded.

## Observed environment

- Production web build: `576754`, release hash `4e71fda896dc6a3755145af5ee328bcf3975f9cf`.
- Production API version: `9`.
- Installed stable desktop host: `0.0.398`, Electron `37.6.0`.
- The locally installed renderer is modified by Equicord, so it is not accepted as a clean request-fingerprint baseline.

## Gateway

- Web bootstrap: `wss://gateway.discord.gg/?encoding=json&v=9&compress=zlib-stream`.
- Desktop bootstrap when `DiscordNative` and the native codecs are present: ETF with `zstd-stream`.
- Normal identify opcode is `2`; resume is `6`; heartbeat/ACK are `1`/`11`.
- The observed identify payload includes token, capabilities (`1734653` without private-channel obfuscation), client properties, optional presence, a legacy-compression flag where applicable, and versioned `client_state`.
- Desktop fast-connect may send an early identify with `is_fast_connect`, an installation identifier, and cached client state before the main renderer completes startup.

## REST preparation

Discord's production request layer adds the account authorization token plus `X-Super-Properties`, `X-Fingerprint` when available, `X-Installation-ID` when available, `Accept-Language`, `X-Discord-Locale`, `X-Discord-Timezone`, and optional debug/routing headers.

Swiftchat currently sends the observed API version and honest locale/timezone headers. It intentionally does not claim to be `Discord Client`, synthesize an official installation/fingerprint, or copy official analytics identifiers. Doing so would be impersonation, would still not guarantee account safety, and could become stale whenever Discord deploys a new build.

## Release gate

Before enabling a full native Gateway by default:

1. Capture only sanitized opcode/header-name/payload-shape fixtures from a clean, unmodified production session.
2. Implement ETF and zstd-stream for the desktop path.
3. Match heartbeat, ACK timeout, resume, invalid-session, reconnect, capability, subscription, and client-state behavior in deterministic tests.
4. Re-run the baseline whenever the production build number changes.
5. Keep a visible experimental warning because protocol parity does not make a third-party normal-account client supported or ban-safe.

