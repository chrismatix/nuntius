# Nuntius

A macOS menu bar app for speech-to-text transcription.

## Features

- 🔒 **Fully local transcription** — uses [WhisperKit](https://github.com/argmaxinc/WhisperKit), no data leaves your Mac
- ☁️ **Cloud option** — connect OpenAI's API if you prefer
- ⌨️ **Global hotkey** — start dictating from anywhere
- 📝 **Text snippets** — define shortcuts that expand into longer text
- 💾 **Save to file** — store transcriptions locally for later
- 🪶 **Lightweight** — lives quietly in your menu bar

## Requirements

- macOS 14.0+
- Apple Silicon recommended (Intel works but slower)

## Installation

```bash
brew install --cask nuntius
```

## Usage

1. Launch Nuntius — it appears in your menu bar
2. Click the icon or press the global hotkey to start dictation
3. Speak, and text appears wherever your cursor is

## Development

### Building from Source

```bash
swift build
```

### Tests

```bash
swift test
```

### Release Build

```bash
./scripts/release.sh --skip-notarize  # local testing
./scripts/release.sh                   # full signed + notarized DMG
```

A cask template lives at `homebrew/Casks/nuntius.rb`.

## License

Public Domain — see [LICENSE](LICENSE). Do whatever you want with it.
