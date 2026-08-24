# Flipper Dashboard for macOS

Flipper Dashboard is a native macOS menu bar app for sending operations saved on a USB-connected Flipper Zero. It discovers remotes and signals from the Flipper's microSD card, so there is no device-specific configuration to edit.

## Features

- Discovers every saved infrared remote and exposes its buttons.
- Discovers saved Sub-GHz files and sends one transmission at a time.
- Pins frequently used operations to the top and remembers their order.
- Recursively counts NFC, LF RFID, BadUSB, miscellaneous, and media files.
- Refreshes every 60 seconds while the dashboard is open without disabling operations.
- Closes an app running on the Flipper before sending, which keeps the CLI available.
- Uses no network service, account, telemetry, or cloud bridge.

The app intentionally does not expose an arbitrary command shell or destructive storage operations.

## Requirements

- macOS 13 or later
- Xcode with the macOS SDK and command-line tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A Flipper Zero connected over USB with a microSD card

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Build and run

```sh
git clone https://github.com/sethwebster/flipper-dashboard.git
cd flipper-dashboard
./Scripts/build-dashboard-app.sh
open ".build/app/Flipper Dashboard.app"
```

The build is ad-hoc signed, so contributors do not need an Apple Developer account or a signing certificate. To install it for your user account, copy `Flipper Dashboard.app` from `.build/app` into `~/Applications`.

A notarized DMG is available from [flipper-dashboard.noisyneighbor.studio](https://flipper-dashboard.noisyneighbor.studio) or the [latest GitHub release](https://github.com/sethwebster/flipper-dashboard/releases/latest).

If more than one Flipper is connected, set `FLIPPER_PORT` in the macOS launch environment before starting the app:

```sh
launchctl setenv FLIPPER_PORT /dev/cu.usbmodemflip_example
open ".build/app/Flipper Dashboard.app"
```

Remove the override later with `launchctl unsetenv FLIPPER_PORT`.

## Using the dashboard

1. Save IR remotes or Sub-GHz signals on your Flipper.
2. Connect the Flipper to the Mac with a data-capable USB cable.
3. Leave the Flipper at its home screen.
4. Open Flipper Dashboard and select the radio-wave icon in the menu bar.
5. Select an IR or Sub-GHz button to send it.

Use radio features only with devices you own or are authorized to control, and follow the frequency and transmission rules for your location.

## Troubleshooting

### Connect the Flipper Zero over USB

Confirm the cable supports data and the Flipper appears as `/dev/cu.usbmodemflip_*`:

```sh
ls /dev/cu.usbmodemflip_*
```

### Multiple Flippers found

Start the app with `FLIPPER_PORT` set to one of the paths shown in the error.

### The app on the Flipper keeps reopening

Return the Flipper to its home screen. Some on-device apps can reopen their USB session and prevent the serial CLI from becoming idle.

### A saved IR file does not appear

The dashboard skips `.ir` files it cannot parse. Open and resave the remote on the Flipper, then refresh the dashboard.

## Development

Run unit tests with:

```sh
swift test
```

Run the read-only integration tests with a Flipper connected:

```sh
RUN_FLIPPER_INTEGRATION=1 swift test
```

The integration suite reads saved data and may close the currently running Flipper app. It does not transmit a signal.

The code is split into two modules:

- `FlipperIRCore` manages the serial CLI, storage discovery, parsing, and transmissions.
- `DashboardBar` provides the SwiftUI menu bar interface.

Maintainers can create a signed and notarized release after storing a `notarytool` profile in Keychain:

```sh
FLIPPER_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
FLIPPER_DEVELOPMENT_TEAM="TEAMID" \
FLIPPER_NOTARY_PROFILE="your-notary-profile" \
./Scripts/release.sh
```

## License

Flipper Dashboard is available under the [MIT License](LICENSE). Flipper Zero is a trademark of Flipper Devices Inc.; this project is independent and is not endorsed by Flipper Devices.
