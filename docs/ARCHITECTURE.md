# Architecture

The application is a SwiftPM-backed macOS executable collected in an Xcode workspace with six local library packages.

- `SwiftchatModels` owns stable domain values and typed snowflakes.
- `DiscordProtocol` owns provider, credential, REST/Gateway-facing boundaries and the mock provider.
- `SwiftchatPersistence` owns account-scoped GRDB storage and migrations.
- `MessageRendering` owns native markdown and message content rendering.
- `MediaPipeline` owns public-media caching and GIF-provider interfaces.
- `SwiftchatPluginSDK` owns capability and permission contracts that can later be represented in WIT.

`AppModel` is a Main Actor observable projection of `ChatProvider` and `SwiftchatDatabase`. Views receive narrow values or the model reference, and no view constructs Discord requests directly.

The embedded login uses a nonpersistent `WKWebView` behind `NSViewRepresentable`. It detects the authenticated web session, validates `/users/@me`, stores the credential through `KeychainCredentialStore`, and replaces the demo provider with `DiscordRESTProvider`. Plugins never receive the credential or its handle.

The `SwiftchatPluginHost` executable is intentionally inert. It establishes a separate signing/process target for the future WASI runtime without loading untrusted code in the app process.
