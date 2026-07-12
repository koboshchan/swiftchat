# Swiftchat

Swiftchat is a native macOS 27 Discord-client research project written in Swift 6.4 and SwiftUI. It includes an interactive demo provider and an experimental native account provider.

## Important warning

Swiftchat is unofficial and is not affiliated with Discord. Discord does not support third-party normal-account clients, and using session credentials outside its supported bot/OAuth APIs may result in account termination. The embedded login captures the authenticated web session, validates it, stores it in the device-only macOS Keychain, and destroys its nonpersistent WebKit data.

## What works now

- Native server rail, channel and DM sidebar, message timeline, member inspector, quick switcher, menus, shortcuts, and Settings scene.
- Mock-backed channel history and live provider events.
- Experimental account bootstrap, guild/channel/DM history, text sending, editing, deletion, and reactions through native REST requests.
- Sending, editing, deleting, replying-ready models, reactions, drafts, optimistic outbox state, file staging, drag-and-drop, emoji, and GIF URL attachments.
- Typed Discord snowflakes, provider and Gateway codec boundaries, Keychain credential store, GRDB account database, markdown renderer, media cache interface, and plugin permission SDK.
- Sandboxed app entitlements and a separate plugin-host executable boundary.

## Run

Requirements: macOS 27 and Xcode 27.

```sh
./script/build_and_run.sh
```

Use `--verify`, `--debug`, `--logs`, or `--telemetry` for the corresponding run mode. The Xcode workspace is `Swiftchat.xcworkspace`.

## Tests

```sh
./script/ci.sh
```

Real credentials, cookie exports, captured authorization headers, account databases, and unsanitized Gateway fixtures must never be committed.
