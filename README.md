# Nuntius

A macOS menu bar app for speech-to-text transcription using [WhisperKit](https://github.com/argmaxinc/WhisperKit) locally or OpenAI cloud.

Audio can be processed entirely on-device, or optionally sent to OpenAI for cloud transcription.

## Requirements

- macOS 14.0+
- Apple Silicon recommended (Intel works but slower)

## Installation

Download the latest DMG from [Releases](../../releases), open it, and drag Nuntius to Applications.

### Homebrew (Cask)

If you publish a Homebrew tap, users can install via:

```bash
brew tap OWNER/tap
brew install --cask nuntius
```

Maintainers: a cask template lives at `homebrew/Casks/nuntius.rb`.

## Building from Source

```bash
swift build
```

## Tests

```bash
swift test
```

For a release build with signing:

```bash
./scripts/release.sh --skip-notarize  # local testing
./scripts/release.sh                   # full signed + notarized DMG
```

## Usage

1. Launch Nuntius — it lives in your menu bar
2. Click the icon or use the global hotkey to start dictation
3. Speak, and text appears wherever your cursor is

## License

Public Domain — see [LICENSE](LICENSE). Do whatever you want with it.
