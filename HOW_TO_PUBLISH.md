# How to publish BarcodeDeck

Step-by-step notes for building and publishing the release artifacts to
Google Play and the App Store. Nothing in this file is specific to any
machine or account.

---

## 0. Before you start (both platforms)

- **Pick the release version** and keep both platforms in sync:
  - Android: `versionCode` (integer, incremented every submission) and
    `versionName` in `barcode-deck-android/app/build.gradle.kts`.
  - iOS: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
    `barcode-deck-ios/project.yml`, then run `xcodegen generate` inside
    `barcode-deck-ios/` to regenerate the Xcode project.
- **Export a JSON backup** of the current deck from the installed app
  (Menu → Export JSON…) so no data can be lost while testing release builds.
- **Run the tests**: Android `gradle testDebugUnitTest`, iOS via Xcode (⌘U).
- **Write a privacy policy** and host it somewhere public (GitHub Pages or a
  gist linked from the README both work — see the template at the bottom).
  Both stores require a URL.

---

## 1. Android (Google Play)

### 1.1 Signing

Play requires release builds signed with a keystore you control:

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -alias barcodedeck-upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

- Keep `upload-keystore.jks` **private and backed up** — never commit it.
- Enroll in **Play App Signing** when creating the app: Google keeps the
  release key, your keystore only signs uploads.

The cleanest way to wire signing in is Android Studio
(*Build → Generate Signed Bundle / APK*), or a `signingConfigs` block in
`app/build.gradle.kts` reading the password from an environment variable or
a local (git-ignored) `keystore.properties`.

### 1.2 Build

```bash
cd barcode-deck-android
gradle bundleRelease        # or use the Gradle wrapper/Android Studio
# → app/build/outputs/bundle/release/app-release.aab
```

### 1.3 Play Console

1. Create the app (name: *Barcode Deck*, default language).
2. Upload the `.aab` to **Internal testing** first and install it from there.
3. **Store listing**: 512×512 icon, 1024×500 feature graphic, 2–8 phone
   screenshots (the ones in `/screenshots` are usable), short + full
   description.
4. **App content** forms:
   - *Data safety*: **no data collected, no data shared** — the app has no
     Internet permission and stores everything in a local database.
   - *Ads*: none. *Content rating*: complete the questionnaire (expected:
     Everyone). *Target audience*: the app is not directed at children and
     does not intentionally collect data from anyone.
5. **Privacy policy**: paste the required URL.
6. Roll out: internal → closed → production.

> Note: the Android manifest explicitly removes the Internet permission that
> ML Kit's transitive dependencies would otherwise merge in. If a future
> dependency needs network access, re-evaluate the Data Safety answers.

---

## 2. iOS (App Store)

### 2.1 Requirements

- A **paid Apple Developer Program** membership: free accounts can only run
  debug builds on personal devices for 7 days and cannot distribute.
- The device used for testing must have Developer Mode enabled.

### 2.2 Version + project

- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`
  (see §0) and regenerate with `xcodegen generate`.

### 2.3 Build & upload

1. Open `barcode-deck-ios/BarcodeDeck.xcodeproj` in Xcode, select the
   *BarcodeDeck* target → *Signing & Capabilities* → choose the team.
2. *Product → Archive*.
3. In the Organizer: *Distribute App → App Store Connect → Upload*.
   (Scriptable alternative: `xcodebuild archive` + `xcodebuild
   -exportArchive` with an `exportOptions.plist` specifying
   `method = app-store`.)

### 2.4 App Store Connect

1. Create the app record (bundle id `dev.barcodedeck.app`).
2. **Privacy nutrition labels**: answer *Data Not Collected* — nothing
   leaves the device. The bundled `PrivacyInfo.xcprivacy` already declares
   no tracking and no collected data types.
3. **Export compliance**: already handled — the Info.plist sets
   `ITSAppUsesNonExemptEncryption` to `false` (the app performs no
   encryption beyond the OS).

### 2.5 Store listing drafts (copy into App Store Connect)

**Name** (30 max): `Barcode Deck`

**Subtitle** (30 max): `Your loyalty cards, one deck`

**Promotional text** (170 max, editable anytime):

> Scan a card once, show it forever. No accounts, no cloud, no tracking.

**Description:**

> Barcode Deck is the simplest way to carry all your shop and loyalty cards.
>
> SCAN ONCE — Point the camera at any barcode. The value is recognized,
> validated and saved with a name you choose.
>
> TAP TO SHOW — Tap a card and your phone becomes the card: the barcode
> fills the screen at maximum brightness in its true physical size, ready
> for any checkout scanner. Pinch to zoom if a particular reader prefers
> it bigger or smaller.
>
> WORKS OFFLINE — No account, no cloud, no tracking. Your cards never
> leave your device.
>
> SHARE A DECK — Export your whole deck as a single JSON file and share
> it with family via AirDrop or Messages. Importing merges cleanly —
> duplicates are skipped automatically.
>
> SCANS & RENDERS — EAN-13, UPC-A, Code 128 and Code 39 (the symbologies
> used by loyalty programs and health cards). All other linear codes are
> stored with their value and shown as text.

**Keywords** (100 max): `barcode,loyalty,cards,wallet,scanner,membership,fidelity,codice,coupon,shop`

**Category:** primary `Utilities`, secondary `Shopping` (or `Lifestyle`).

**Price:** Free, no In-App Purchases. **Age rating:** 4+ (no user-generated
content, no web content — the questionnaire is straightforward).

### 2.6 Review notes (paste into App Review information)

> Barcode Deck stores barcoded shop/loyalty cards and displays them
> full-screen for scanning at checkout. Demo: launch, tap +, scan or type a
> value (e.g. 4006381333931), save, tap the card — the phone shows the
> barcode full-screen. No account needed. The camera permission is for
> barcode scanning only.

### 2.7 Screenshots

| Device set | How to capture |
| --- | --- |
| 6.9" iPhone (required) | Simulator: iPhone 16/17 Pro Max → `xcrun simctl io "device" screenshot` |
| 6.5" iPhone (required) | Simulator: iPhone 11/13/14 Plus sized device |

Suggested shots: (1) list with a few cards, (2) presentation mode landscape
with a barcode, (3) add form with validation, (4) delete with the undo bar.
The debug launch arguments (`--debug-present-demo`, `--debug-show-add`)
make reproducible screenshot states easy.

### 2.8 Good to know

- The **bundle ID is permanent** once published — `dev.barcodedeck.app`.
- Old `cardbox-export` JSON files remain importable (the type marker is
  accepted for backward compatibility).
- **Rejected for metadata?** The most common cause: screenshots showing
  content that is not in the app — the debug flags above keep them honest.

---

## 3. Privacy policy (template)

The app makes the following true claims — keep the policy in sync with the
code if anything ever changes:

> Barcode Deck stores your cards only on your device, in the app's own
> database. It has no server, no account system, and no analytics, and it
> does not collect, transmit, or share any personal data. The camera is
> used exclusively to recognize barcodes on-device; nothing is recorded or
> uploaded. Export and import happen through files you explicitly create
> and share. The Android version does not request the Internet permission.

---

## 4. Final checklist

- [ ] Version numbers bumped and in sync on both platforms
- [ ] Unit tests green (Android) and the app smoke-tested on a real device
- [ ] Release build made from a clean clone
- [ ] Store listings complete (icon, graphic, screenshots, descriptions)
- [ ] Data Safety / privacy nutrition labels answered (nothing collected)
- [ ] Privacy policy URL live on both stores
- [ ] JSON backup of the current deck exported
