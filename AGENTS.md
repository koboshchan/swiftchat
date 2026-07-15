# SwiftChat agent guidance

This file applies to the entire repository.

SwiftChat is an interactive, native macOS Discord client written in Swift and SwiftUI. It is not intended to be a self-bot, spam tool, or unattended account-automation system: user-visible actions in the app initiate account actions. Its purpose is to provide a fast, resource-efficient, Liquid Glass client experience without Discord's Electron runtime.

SwiftChat is nevertheless unofficial and uses a normal Discord account session through protocol surfaces that Discord does not document or support as a third-party-client API. Treat protocol accuracy and conservative failure handling as account-safety requirements. No degree of parity can guarantee that Discord will accept the client or refrain from account action.

## Core implementation rule: research before writing

Do not guess Discord-facing behavior. Before adding or changing anything that talks to Discord—including REST, Gateway, voice/video signaling, authentication, messages, DMs, reactions, emoji, attachments, presence, profiles, member lists, or settings—agents MUST study all three reference categories below:

1. The corresponding behavior in Paicord.
2. The corresponding behavior in Swiftcord v1.
3. The exact behavior of a current, clean, unmodified official Discord client.

Also consult Discord's current public API documentation, status/error-code documentation, and rate-limit documentation wherever applicable. Public documentation is authoritative for the behavior it covers, but it does not cover every normal-client route or payload.

Do not implement the production call until this comparison is complete. If one reference is unavailable or does not implement the feature, document that fact and use the remaining references; do not silently substitute assumptions.

## Paicord and Swiftcord v1 review

- Trace the complete feature path, not just the endpoint string: UI trigger, state/cache lookup, Gateway dependency, request construction, headers, body, response decoding, error handling, retries, and invalidation.
- Swiftcord v1 is currently non-functional and old. Its code is still a valuable design and protocol reference, but every detail must be verified against current Discord behaviour before reuse.
- Paicord and Swiftcord are independent clients, not sources of truth. Identify where they differ from each other and from the current official client.

## Official-client protocol examination

Use a clean, unmodified official Discord web or desktop client and an account/session the user is authorized to inspect. Compare the exact network and Gateway behavior needed for the feature:

- HTTP method, API version, route, path parameters, query parameters, and content type.
- Request body shape, field presence versus omission, nullability, types, nonce/idempotency fields, attachment metadata, reply/message references, and context fields.
- Header names, values, and provenance: distinguish stable client metadata, values derived from the real local environment, values issued by Discord, and per-session/per-request values.
- Number of calls caused by one UI action, call ordering, concurrency, debouncing, cancellation, batching, pagination, lazy loading, prefetching, and cache reuse.
- Gateway opcode and payload shape, capabilities, client state, subscriptions, sequence handling, heartbeat/ACK behavior, resume, reconnect, and invalid-session behavior.
- Success status, error status and Discord error code, response headers, rate-limit bucket/scope, response-body shape, and cache invalidation caused by the operation.

Capture only what is needed to understand protocol semantics. Never commit or share account tokens, authorization headers, cookies, message bodies, personal data, server-issued fingerprints/installation identifiers, or unsanitized captures. Do not replay captured credentials. Values issued by Discord must come from the legitimate flow that issues them; never hard-code or borrow them from another account/session.

Protocol parity is for compatibility, correctness, predictable performance, and avoiding malformed or anomalous request behavior. Do not add hidden unattended actions, spam behavior, challenge bypasses, or logic that continues sending after Discord has restricted the account.

## Required implementation record

Every Discord-facing change must include an implementation note in its PR/commit description or associated repository documentation containing:

- Official Discord documentation consulted.
- Paicord repository revision and relevant findings.
- Swiftcord v1 repository revision and relevant findings.
- Official-client version/build, observation date, and a sanitized call-flow description.
- A comparison table listing route/payload/header/sequencing differences between all references and SwiftChat.
- The chosen behavior and why it matches the current official client or deliberately differs.
- Expected request count for cold cache, warm cache, repeated UI action, and failure/retry cases.
- Rate-limit, account-restriction, rollback, and testing considerations.

Update `docs/PROTOCOL_BASELINE.md` when a change establishes or supersedes a repository-wide protocol baseline. Never present a stale observation as current.

## REST request safety and parity

- Route authenticated requests through the shared transport and rate-limit coordinator. Do not create one-off authenticated `URLSession` paths that bypass common scheduling, logging, or shutdown behavior.
- Match the official client's endpoint and payload semantics for the same user action. Do not add extra “just in case” requests or speculative probes.
- Do not hard-code rate limits. Track the server's `X-RateLimit-Bucket`, major parameters, scope, remaining count, reset time, and `Retry-After`/`retry_after` values.
- A fixed global delay can be a temporary safety ceiling, but it is not a replacement for Discord's bucket model. Scheduling must prevent bursts without making the client unnecessarily slow.
- On `429`, pause the affected bucket for the full server-provided duration. Honor global/shared scope. Never probe or retry early.
- Treat unexpected `401`, `403`, repeated `404`, malformed-request responses, verification requirements, and account restriction codes as stop conditions. Open the safety circuit and prevent retry storms.
- Mutating requests must not be automatically retried after an ambiguous result. Use the same nonce/idempotency behavior as the current official client and reconcile the resulting Gateway/REST event before permitting another send.
- Retry reads only when the operation is safe and the observed official behavior supports it. Bound attempts and use cancellation-aware backoff.
- Coalesce identical reads, deduplicate in-flight loads, cache stable data, paginate deliberately, cancel superseded work, and cap concurrency.
- Validate payloads before transmission: channel type, permissions when known, required fields, size/count limits, and attachment metadata.
- Log sanitized route templates, methods, status/error codes, request counts, bucket identifiers, and timing. Never log credentials or message content.

## Gateway requirements

- Maintain an explicit, testable state machine for connect, hello, identify/resume, heartbeat, ACK tracking, ready, reconnect, invalid session, backoff, and shutdown.
- Match current official-client identify, capabilities, client-state, compression/encoding, and subscription semantics only after comparing them with Paicord and Swiftcord v1.
- Metadata in identify/request properties must be understood and sourced correctly. Do not blindly paste a captured blob or claim values that belong to a different account/session/device.
- Track heartbeat ACKs; do not merely send periodic heartbeats. A missing ACK must close/reconnect according to observed protocol behavior.
- Prefer resume over a fresh identify when the session is resumable. Bound reconnect attempts and never reconnect in a tight loop.
- Add deterministic fixtures for every opcode and transition used by a new feature.

## Direct-message guardrail

DM behavior requires extra review because a SwiftChat DM send has already triggered an account disablement.

- Distinguish opening/creating a DM channel, loading an existing DM, and sending into it. Do not create/open a DM as part of every send.
- Before changing or enabling a DM path, capture and compare one equivalent manual action in the current official client and inspect the full Paicord and Swiftcord v1 paths.
- Match the official request body, nonce, context fields, call ordering, and Gateway reconciliation. Small omissions can change how Discord classifies the operation.
- Serialize duplicate open/create attempts and deduplicate sends. Never automatically retry a send after an ambiguous timeout.
- Handle Discord error `40003` (opening DMs too quickly), `40004` (sending temporarily disabled), verification/challenge responses, and connection revocation as immediate session-wide stop conditions.
- Keep incomplete DM creation/sending behavior visibly experimental and disabled by default until fixture tests and the implementation record are complete.

## Testing and live-account rules

- Default to mocked transports, sanitized fixtures, deterministic clocks, and synthetic accounts/guilds. All core behavior must be testable with Discord networking disabled.
- Add request-contract tests for method, route, query, headers, body, status/error handling, rate-limit scheduling, retry count, and mutation nonce behavior.
- Add request-budget tests for any feature that can fan out. Fail tests when a UI action unexpectedly produces extra requests.
- Do not make real Discord calls merely because a build or unit test runs. Live tests require an explicit manual action and a stated expected call sequence.
- Keep live tests narrow: one feature, one manual action, and one inspected result at a time. Do not use an account whose loss would be unacceptable.
- Stop all live traffic immediately after any CAPTCHA, verification request, unexpected `401`/`403`, `429`, temporary-send restriction, DM-open-too-fast response, connection revocation, or other trust-and-safety signal. Do not retry to see whether the restriction cleared.
- After a stop condition, preserve sanitized diagnostics, disable the affected path, compare it again with all three references, and complete a root-cause review before another live test.

## Scope boundary

- Do not add self-bot features, unattended account actions, bulk messaging, spam, scraping, mass-DM behavior, or token sharing. These are outside SwiftChat's purpose.
- Do not bypass CAPTCHAs, verification challenges, rate limits, permission checks, account restrictions, or other safety controls.
- Do not claim affiliation with Discord or claim that SwiftChat is ban-safe.
- Do not weaken Keychain storage, secret redaction, the offline network switch, or the REST safety circuit for convenience.

## Completion checklist

Do not consider a Discord-facing change complete until all applicable answers are yes:

- Were Paicord, Swiftcord v1, the current official client, and applicable official documentation reviewed?
- Are exact reference revisions/builds and sanitized findings recorded?
- Does the call flow match the official client's current semantics, or is every deliberate difference justified?
- Are request count, ordering, concurrency, caching, pagination, cancellation, and deduplication explicit?
- Are Discord's bucket headers and server-provided retry intervals handled centrally?
- Are mutations safe from automatic duplicate actions?
- Do authentication, permission, malformed-request, challenge, and restriction responses fail closed?
- Are tests runnable without a live Discord account and free of secrets/personal data?
- Are DM and high-fan-out features gated until their contract tests and request budgets pass?
- Would an account restriction stop all related traffic immediately?
