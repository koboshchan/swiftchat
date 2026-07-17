# Discord production protocol baseline

Updated on 17 July 2026 from Discord's public production bootstrap, public production assets, and a clean signed/notarized stable desktop host. No account token, cookie, message body, authorization header, personal payload, or authenticated traffic was recorded. The detailed comparisons are in `GATEWAY_TYPING_IMPLEMENTATION.md` and `NATIVE_AUTH_IMPLEMENTATION.md`.

## Observed environment

- Production web build: `579073`, build ID `da0a6c522614d5f65e35f81fe0163fa94db26df5`.
- Production API version: `9`.
- Clean signed/notarized stable desktop host: `0.0.401`, with Electron framework `37.6.0`. The locally launched renderer had third-party modifications, so it was excluded from protocol evidence.

## Gateway

- Web bootstrap: `wss://gateway.discord.gg/?encoding=json&v=9&compress=zlib-stream`.
- Desktop bootstrap when `DiscordNative` and the native codecs are present: ETF with `zstd-stream`.
- Normal identify opcode is `2`; resume is `6`; heartbeat/ACK are `1`/`11`.
- SwiftChat uses the current web JSON/`zlib-stream` path and the documented opcode-1 heartbeat. It deliberately does not copy the current client's undocumented QoS heartbeat envelope.
- The observed identify payload includes token, capabilities (`1734653` without private-channel obfuscation), client properties, optional presence, a legacy-compression flag where applicable, and versioned `client_state`.
- Desktop fast-connect may send an early identify with `is_fast_connect`, an installation identifier, and cached client state before the main renderer completes startup.

## REST preparation

Discord's production request layer adds the account authorization token plus `X-Super-Properties`, `X-Fingerprint` when available, `X-Installation-ID` when available, `Accept-Language`, `X-Discord-Locale`, `X-Discord-Timezone`, and optional debug/routing headers.

SwiftChat sends the observed API version and one consistent Paicord-shaped metadata envelope across session validation, REST, and Gateway Identify. It uses the current observed Discord desktop/web versions, Paicord's current Chromium/header shape, and real locale/timezone/kernel/architecture values. Native sign-in obtains and persists only the fingerprint issued by Discord's `/experiments` flow; SwiftChat does not synthesize an installation ID/fingerprint or copy cookies, analytics identifiers, or other server-issued values.

Native authentication follows Paicord revision `694761c1938b73bb60bd58942674dfe73aab1135` for fingerprint, login, MFA, hCaptcha, and bounded transport retry behavior. SwiftChat pins Paicord's hCaptcha dependency at `29de12bd290c5cc9c61b3e3c15fe9a9d21449465`, preserves Discord's `should_serve_invisible` challenge metadata, and reveals the embedded verifier only when the SDK reports that interaction is required. Public Discord documentation does not document normal-account password-login routes; see the implementation record for the exact comparison and limitations.

Native QR authentication follows the same Paicord revision's remote-auth v2 flow: one `wss://remote-auth-gateway.discord.gg/?v=2` session, an ephemeral RSA-2048 SPKI public key, OAEP-SHA256 nonce/user/token decryption, a `https://discord.com/ra/{server-issued fingerprint}` QR value, one ticket exchange at `POST /users/@me/remote-auth/login`, and one current-user validation before Keychain storage. Paicord routes a CAPTCHA from that ticket exchange through its shared interactive callback and permits exactly one user-completed replay; SwiftChat now does the same while retaining the one-use RSA key until the exchange is completed or cancelled. The current public client assets expose the same `/ra/:remoteAuthFingerprint` and remote-auth REST route family, while Discord's public API documentation does not document the remote-auth WebSocket. Swiftcord v1 had no native implementation and delegated QR login to its embedded web view.

Current message creation uses a Discord-epoch snowflake nonce with a 12-bit local sequence, the `chat_input` context header, and `mobile_network_type: "unknown"`. The previous Unix-epoch nonce was malformed and decoded decades into the future; deterministic contract tests prevent its recurrence. Any safety-sensitive response stops both REST and Gateway activity for the provider session.

## Release gate

Before enabling the experimental normal-account connector broadly:

1. Capture only sanitized opcode/header-name/payload-shape fixtures from a clean, unmodified production session.
2. Re-evaluate whether ETF/`zstd-stream` provides a material benefit over the supported production JSON/`zlib-stream` path; do not treat native-only behavior as identity metadata to copy.
3. Keep heartbeat, ACK timeout, resume, invalid-session, reconnect, capability, subscription, and client-state behavior covered by deterministic tests.
4. Re-run the baseline whenever the production build number changes.
5. Keep a visible experimental warning because protocol parity does not make a third-party normal-account client supported or ban-safe.
