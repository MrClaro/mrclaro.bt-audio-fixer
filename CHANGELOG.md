# Changelog

All notable changes to `mrclaro.bt-audio-fixer` are documented in this file.

## [1.0.0] - 2026-11-13

### Added
- Automatic multi-device discovery and BLE-only trap detection (`0000110b` Audio Sink / `0000110d` A2DP / `0000111e` HFP / `00001108` HSP vs. GATT-only LE state).
- Automatic exclusion of BLE HID peripherals (`00001812` / `00001124` mice, keyboards, tablets).
- **Smart Connect (`A2DP`)** with automatic fallback to `BR/EDR` re-pairing and automatic PipeWire default audio output switching.
- **Force BR/EDR Re-pair** using `bluetoothctl scan bredr` to bypass BLE advertisements.
- **Scan Classic Audio (`BR/EDR`)** mode to discover dual-mode headphones on Classic Bluetooth.
- **Layered USB Stack Reset (`btusb`)** combining user-space power cycling with kernel `btusb` module reload via Polkit (`pkexec`).
- **Background Auto-Heal (`autoHealBle`)** with per-device cooldown to automatically recover headphones that connect in BLE-only mode.
- Live translations for English (`en`), Brazilian Portuguese (`pt-BR`), and European Portuguese (`pt`).
- Unit, security regression, and cross-file wiring test suites (`tests/model.test.js`, `tests/wiring.test.js`) and GitHub Actions CI.
