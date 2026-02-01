# Nuntius Release Guide (Homebrew Cask)

This guide covers building, signing, notarizing, and distributing Nuntius via a Homebrew cask.

## Table of Contents

1. [Quick Start (Unsigned)](#quick-start-unsigned)
2. [Prerequisites (Signed Release)](#prerequisites-signed-release)
3. [One-Time Setup](#one-time-setup)
4. [Releasing a New Version](#releasing-a-new-version)
5. [Local Release (Manual)](#local-release-manual)
6. [Automated Release (GitHub Actions)](#automated-release-github-actions)
7. [Homebrew Cask Setup](#homebrew-cask-setup)
8. [Troubleshooting](#troubleshooting)
9. [Release Checklist](#release-checklist)

---

## Quick Start (Unsigned)

**For sharing with friends** - no Apple Developer account needed.

```bash
./scripts/release.sh --skip-sign
```

Output: `.build/dmg/Nuntius.dmg`

### For recipients:
When opening an unsigned app, macOS will block it. To bypass:

**Option 1**: Right-click the app → "Open" → Click "Open" in the dialog

**Option 2**: Remove quarantine flag:
```bash
xattr -cr /Applications/Nuntius.app
```

---

## Prerequisites (Signed Release)

For public distribution (avoids security warnings), you need:

- **Apple Developer Account** ($99/year) with Developer ID capabilities
- **Xcode Command Line Tools** installed (`xcode-select --install`)
- **Developer ID Application certificate** in your keychain

---

## One-Time Setup

### 1. Developer ID Certificate

You need a "Developer ID Application" certificate to sign apps for distribution outside the App Store.

1. Open Xcode → Settings → Accounts → Manage Certificates
2. Click `+` → "Developer ID Application"
3. The certificate will be added to your keychain

Verify it's installed:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. App-Specific Password for Notarization

Apple requires notarization for all distributed apps. Create an app-specific password:

1. Go to https://appleid.apple.com/account/manage
2. Sign in → App-Specific Passwords → Generate
3. Name it "Nuntius Notarization" and save the password

Store credentials in your keychain for the release script:
```bash
xcrun notarytool store-credentials "nuntius-notary" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Find your Team ID at https://developer.apple.com/account → Membership.

### 3. GitHub Secrets (for automated releases)

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret | Description |
|--------|-------------|
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded .p12 export of your Developer ID certificate |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

To export your certificate as base64:
```bash
# Export from Keychain Access as .p12, then:
base64 -i certificate.p12 | pbcopy
```

---

## Releasing a New Version

### Version Numbering

Update the version in `Info.plist` before releasing:

```bash
# Set version string (e.g., 1.2.0)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.0" Info.plist

# Set build number (increment for each build)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 42" Info.plist
```

- `CFBundleShortVersionString`: User-visible version (1.2.0)
- `CFBundleVersion`: Build number (monotonic)

---

## Local Release (Manual)

Use the release script for local builds:

```bash
# Full release with notarization
./scripts/release.sh

# Skip notarization (for testing)
./scripts/release.sh --skip-notarize
```

The script will:
1. Build the app in release mode
2. Create the app bundle
3. Sign everything with your Developer ID (unless skipped)
4. Create a DMG
5. Submit to Apple for notarization (unless skipped)
6. Staple the notarization ticket

Output: `.build/dmg/Nuntius.dmg`

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SIGNING_IDENTITY` | `Developer ID Application` | Code signing identity |
| `NOTARY_PROFILE` | `nuntius-notary` | Keychain profile for notarization |

---

## Automated Release (GitHub Actions)

The easiest way to release is via GitHub Actions:

### Creating a Release

1. **Update version** in `Info.plist` and commit
2. **Create and push a tag**:
   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```
3. The workflow automatically:
   - Builds the app
   - Signs with your Developer ID
   - Notarizes with Apple
   - Creates a signed DMG
   - Creates a GitHub Release with the DMG

### Manual Workflow Trigger

You can also trigger the workflow manually:

1. Go to Actions → Release → Run workflow
2. Optionally specify a version number

---

## Homebrew Cask Setup

### 1. Create a Tap

Create a separate repo, e.g. `homebrew-tap`.

Directory layout:
```
Casks/nuntius.rb
```

### 2. Add the Cask

`Casks/nuntius.rb`
```ruby
cask "nuntius" do
  version "1.2.3"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/OWNER/REPO/releases/download/v#{version}/Nuntius-#{version}.dmg",
      verified: "github.com/OWNER/REPO/"
  name "Nuntius"
  desc "Local speech-to-text transcription for macOS"
  homepage "https://github.com/OWNER/REPO"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Nuntius.app"
end
```

### 3. Publish the Tap

Push the tap repo to GitHub. Users install via:
```bash
brew tap OWNER/tap
brew install --cask nuntius
```

### 4. Update the Cask on Each Release

After each release:
1. Compute the new checksum:
   ```bash
   shasum -a 256 Nuntius-1.2.3.dmg
   ```
2. Update `version` and `sha256` in `Casks/nuntius.rb`.
3. Commit and push the tap.

Users update via:
```bash
brew upgrade --cask nuntius
```

---

## Troubleshooting

### "Developer ID Application" certificate not found

```bash
# List available signing identities
security find-identity -v -p codesigning
```

If missing, create one in Xcode or download from Apple Developer portal.

### Notarization fails with "Invalid credentials"

```bash
# Re-store credentials
xcrun notarytool store-credentials "nuntius-notary" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Notarization fails with code signing issues

Check the notarization log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "nuntius-notary"
```

Common issues:
- Missing `--options runtime` in codesign
- Unsigned nested frameworks
- Hardened runtime not enabled

### App shows "damaged" or "unidentified developer"

The app wasn't properly signed or notarized. Verify:
```bash
# Check signature
codesign --verify --deep --strict --verbose=2 /path/to/Nuntius.app

# Check notarization
spctl --assess --type exec -vvv /path/to/Nuntius.app
```

---

## Release Checklist

- [ ] Update `CFBundleShortVersionString` in Info.plist
- [ ] Update `CFBundleVersion` in Info.plist (must be higher than previous)
- [ ] Test the app locally
- [ ] Commit changes
- [ ] Create and push version tag: `git tag v1.2.0 && git push origin v1.2.0`
- [ ] Verify GitHub Actions workflow completes
- [ ] Verify GitHub Release contains the DMG
- [ ] Update Homebrew cask (`Casks/nuntius.rb`) in your tap
- [ ] Test `brew install --cask nuntius` from the tap
