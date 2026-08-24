# Changelog

## Unreleased

- Keep operation buttons enabled during background inventory refreshes.
- Move inventory scans off the main actor and cancel a scan before sending.
- Poll every 60 seconds instead of every 15 seconds.
- Pin frequently used IR and Sub-GHz operations to an ordered section at the top.
- Preserve pinned operations between launches.

## 1.0.0, 2026-08-23

- Discover saved infrared remotes and expose parsed or raw signals from the macOS menu bar.
- Discover and transmit saved Sub-GHz files one time per click.
- Count NFC, LF RFID, BadUSB, miscellaneous, and media files recursively.
- Refresh the connected Flipper inventory every 15 seconds while the dashboard is open.
- Build as a universal, Developer ID-signed, notarized macOS application.
