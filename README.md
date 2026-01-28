# Nuntius

A macOS menu bar app for speech-to-text transcription using [WhisperKit](https://github.com/argmaxinc/WhisperKit) locally or OpenAI cloud.

Audio can be processed entirely on-device, or optionally sent to OpenAI for cloud transcription.

## Requirements

- macOS 14.0+
- Apple Silicon recommended (Intel works but slower)

## Installation

Download the latest DMG from [Releases](../../releases), open it, and drag Nuntius to Applications.

## Building from Source

```bash
swift build
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

## Auto-Updates

Nuntius uses [Sparkle](https://sparkle-project.org/) for auto-updates. On first launch (after the second run), it will check for updates automatically.

### Setting up EdDSA keys (maintainers)

1. Download Sparkle from [releases](https://github.com/sparkle-project/Sparkle/releases)
2. Run `./bin/generate_keys` to create a keypair (stored in Keychain)
3. Export the private key: `./bin/generate_keys -x sparkle_private_key`
4. Add the private key as `SPARKLE_EDDSA_PRIVATE_KEY` secret in GitHub
5. Add your public key to `SUPublicEDKey` in Info.plist

## License

Public Domain — see [LICENSE](LICENSE). Do whatever you want with it.
