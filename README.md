# SwiftChat

SwiftChat is a native macOS 27 Discord-client research project written in Swift 6.4 and SwiftUI. It includes a flag-gated, fully offline mock-data mode and an experimental native account provider.

## Important warning

DO NOT USE THIS CLIENT IN ITS CURRENT STATE. SOME ACTIONS, INCLUDING SENDING DMS OR LOADING EMOJIS, MAY GET YOUR ACCOUNT TEMPORARILY DISABLED (THIS HAS HAPPENED TWICE). USE AT YOUR OWN RISK.
SwiftChat is unofficial and is not affiliated with Discord. Discord does not support third-party normal-account clients, and using session credentials outside its supported bot/OAuth APIs may result in account termination.

## What works now

- Native server rail, channel and DM sidebar, message timeline, member inspector, quick switcher, menus, shortcuts, and Settings scene.
- Mock-backed channel history and live provider events.
- Experimental account bootstrap, guild/channel/DM history, text sending, editing, deletion, and reactions through native REST requests.
- Native password, MFA, and user-completed hCaptcha sign-in without an embedded Discord login page.
- Native voice and camera video with device controls, Opus/H.264 media, voice-server migration, and DAVE support.
- Sending, editing, deleting, replying-ready models, reactions, drafts, optimistic outbox state, file staging, drag-and-drop, emoji, and GIF URL attachments.
- Typed Discord snowflakes, provider and Gateway codec boundaries, Keychain credential store, GRDB account database, markdown renderer, media cache interface, and plugin permission SDK.
- Sandboxed app entitlements and a separate plugin-host executable boundary.

## Run

Requirements: macOS 27 and Xcode 27.

```sh
./script/build_and_run.sh
```

Use `--verify`, `--debug`, `--logs`, or `--telemetry` for the corresponding run mode. The Xcode workspace is `Swiftchat.xcworkspace`.

Use `./script/build_and_run.sh --offline` for fully offline mock-data testing. `--demo` remains a compatibility alias for the same mode; normal launch never constructs or displays mock data.

`App/Packaging/Swiftchat.icon` is the default app icon. Self-builds can opt into the bundled flower design with:

```sh
SWIFTCHAT_APP_ICON="SwiftChat Flower.icon" ./script/build_and_run.sh
```

## Tests

```sh
./script/ci.sh
```

Real credentials, cookie exports, captured authorization headers, account databases, and unsanitized Gateway fixtures must never be committed.
