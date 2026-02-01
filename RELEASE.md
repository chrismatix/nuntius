# Nuntius Release Guide

This guide covers everything needed to build and distribute Nuntius outside the Mac App Store.

## Table of Contents

1. [Quick Start (Unsigned)](#quick-start-unsigned)
2. [Prerequisites (Signed Release)](#prerequisites-signed-release)
3. [One-Time Setup](#one-time-setup)
4. [Releasing a New Version](#releasing-a-new-version)
5. [Local Release (Manual)](#local-release-manual)
6. [Automated Release (GitHub Actions)](#automated-release-github-actions)
7. [How Auto-Updates Work](#how-auto-updates-work)
8. [Troubleshooting](#troubleshooting)

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
- **Sparkle EdDSA key pair** for signing updates

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

### 3. Sparkle EdDSA Keys

Sparkle uses EdDSA signatures to verify updates. Generate a key pair:

```bash
# Download Sparkle tools
curl -L -o /tmp/Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz"
mkdir -p /tmp/sparkle
tar -xf /tmp/Sparkle.tar.xz -C /tmp/sparkle

# Generate key pair
/tmp/sparkle/bin/generate_keys
```

This outputs:
- **Private key**: Store securely (needed for signing updates)
- **Public key**: Add to Info.plist as `SUPublicEDKey`

Add the public key to `Info.plist`:
```xml
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_HERE</string>
```

### 4. Configure Appcast URL

Add the Sparkle feed URL to `Info.plist`:
```xml
<key>SUFeedURL</key>
<string>https://chrismatix.github.io/nuntius/appcast.xml</string>
```

### 5. GitHub Secrets (for automated releases)

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret | Description |
|--------|-------------|
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded .p12 export of your Developer ID certificate |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle private key for signing updates |

To export your certificate as base64:
```bash
# Export from Keychain Access as .p12, then:
base64 -i certificate.p12 | pbcopy
```

### 6. Enable GitHub Pages

The appcast.xml is hosted on GitHub Pages:

1. Go to repository Settings → Pages
2. Source: "GitHub Actions"

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
- `CFBundleVersion`: Build number, must always increase for Sparkle updates

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
2. Create the app bundle with Sparkle.framework
3. Sign everything with your Developer ID
4. Create a DMG
5. Submit to Apple for notarization (unless skipped)
6. Staple the notarization ticket

Output: `.build/dmg/Nuntius.dmg`

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SIGNING_IDENTITY` | `Developer ID Application` | Code signing identity |
| `NOTARY_PROFILE` | `nuntius-notary` | Keychain profile for notarization |

### Manual Sparkle Signing

After creating the DMG, sign it for Sparkle updates:

```bash
/tmp/sparkle/bin/sign_update .build/dmg/Nuntius.dmg --ed-key-file /path/to/private-key
```

This outputs the signature attributes to include in your appcast.xml.

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
   - Signs the update for Sparkle
   - Creates a GitHub Release with the DMG
   - Updates the appcast.xml on GitHub Pages

### Manual Workflow Trigger

You can also trigger the workflow manually:

1. Go to Actions → Release → Run workflow
2. Optionally specify a version number

---

## How Auto-Updates Work

Nuntius uses [Sparkle](https://sparkle-project.org/) for automatic updates:

1. App checks `SUFeedURL` (appcast.xml) periodically
2. Compares `CFBundleVersion` with versions in appcast
3. If newer version available, prompts user to update
4. Downloads DMG, verifies EdDSA signature
5. Installs update and relaunches

### Appcast Structure

The `appcast.xml` file lists available versions:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Nuntius Updates</title>
    <link>https://chrismatix.github.io/nuntius/appcast.xml</link>
    <item>
      <title>Version 1.2.0</title>
      <pubDate>Mon, 01 Jan 2024 12:00:00 +0000</pubDate>
      <sparkle:version>42</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/chrismatix/nuntius/releases/download/v1.2.0/Nuntius-1.2.0.dmg"
        sparkle:edSignature="..."
        sparkle:length="..."
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

Key fields:
- `sparkle:version`: Must match `CFBundleVersion` and always increase
- `sparkle:edSignature`: EdDSA signature from `sign_update`
- `sparkle:length`: File size in bytes

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

### Sparkle updates not working

1. Verify `SUFeedURL` is in Info.plist
2. Check appcast.xml is accessible at the URL
3. Ensure `sparkle:version` in appcast is greater than installed version
4. Verify EdDSA signature matches public key in app

Test the appcast:
```bash
curl -s https://chrismatix.github.io/nuntius/appcast.xml
```

### GitHub Actions fails to sign

Ensure secrets are correctly set:
- `DEVELOPER_ID_CERTIFICATE_P12` must be base64-encoded
- Certificate password must match the .p12 export password
- Apple credentials must be valid

---

## Release Checklist

- [ ] Update `CFBundleShortVersionString` in Info.plist
- [ ] Update `CFBundleVersion` in Info.plist (must be higher than previous)
- [ ] Test the app locally
- [ ] Commit changes
- [ ] Create and push version tag: `git tag v1.2.0 && git push origin v1.2.0`
- [ ] Verify GitHub Actions workflow completes
- [ ] Verify GitHub Release contains the DMG
- [ ] Verify appcast.xml is updated on GitHub Pages
- [ ] Test auto-update from previous version
