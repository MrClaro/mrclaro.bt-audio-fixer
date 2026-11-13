# Contributing to `mrclaro.bt-audio-fixer`

Contributions, bug reports, and translations for additional Omarchy locales are welcome!

## Local Development

Clone or work directly inside `~/.config/omarchy/plugins/mrclaro.bt-audio-fixer/`:

```bash
# Rescan and enable on the Omarchy bar
omarchy-shell shell rescanPlugins
omarchy plugin enable mrclaro.bt-audio-fixer --before omarchy.bluetooth
```

Any edits saved to `Panel.qml`, `Model.js`, or `i18n/*.json` hot-reload automatically in `omarchy-shell`.

## Running Checks Before Submitting a PR

Every change must pass all three checks with zero warnings:

```bash
# 1. Validate the Omarchy plugin manifest and entry points
omarchy plugin validate .

# 2. Run the Model unit & security regression suite
node tests/model.test.js

# 3. Run the cross-file contract, i18n parity, and shell syntax checks
node tests/wiring.test.js
```

## Security & UI Guidelines

- Never use bare `Text {}` in QML; always use `PlainText {}` (which enforces `textFormat: Text.PlainText`) and sanitize external strings through `Model.plainText(...)`.
- Never interpolate unvalidated strings into shell commands; pass arguments via argv arrays to `scripts/bt-audio-ctl.sh` and validate MAC addresses against `^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$`.
- Keep all translations in sync across `i18n/en.json`, `i18n/pt-BR.json`, and `i18n/pt.json`.
