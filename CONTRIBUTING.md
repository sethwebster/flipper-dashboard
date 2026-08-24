# Contributing

Contributions are welcome.

1. Fork the repository and create a focused branch.
2. Make the smallest change that solves the problem.
3. Run `swift test`.
4. Run `./Scripts/build-dashboard-app.sh` for UI or build-system changes.
5. Open a pull request that explains the behavior change and how you verified it.

Do not commit captured signals, serial-device output, Apple signing identifiers, or other personal device data. Tests should use synthetic fixtures. Live tests must remain opt-in through `RUN_FLIPPER_INTEGRATION=1` and must not transmit signals.
