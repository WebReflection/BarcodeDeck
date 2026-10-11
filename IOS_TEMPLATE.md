# IOS_TEMPLATE — publishing Barcode Deck to the App Store

A fill-in walkthrough for one release cycle. Every "→ put this" is the
exact value or copy to enter. Project constants are already filled in;
per-release values (versions, release notes) are marked ✏️.

Companion to [`HOW_TO_PUBLISH.md`](HOW_TO_PUBLISH.md) — that file explains
the *why*, this walks the *clicks*.

---

## Constants (same every release)

| Field | Value |
| --- | --- |
| Bundle ID | `dev.barcodedeck.app` |
| Min iOS | 17.0 |
| Version fields live in | `barcode-deck-ios/project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) |
| Export compliance | Pre-handled — `Info.plist` sets `ITSAppUsesNonExemptEncryption = false` |
| Privacy manifest | `BarcodeDeck/PrivacyInfo.xcprivacy` (no tracking, no collected data) |
| Data collected | **None** — everything stays on device |
| Price | Free, no IAP |

## 0. Before you start

- [ ] Paid Apple Developer Program membership required for distribution.
- [ ] Export a JSON backup of your current deck from the installed app.
- [ ] Tests green:

```bash
cd barcode-deck-ios
xcodegen generate   # after any project.yml or file-set change
xcodebuild test -project BarcodeDeck.xcodeproj -scheme BarcodeDeck \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## 1. ✏️ Set the version

In `barcode-deck-ios/project.yml`:

| Field | Put this |
| --- | --- |
| `MARKETING_VERSION` | ✏️ e.g. `1.0.1` — match Android `versionName` |
| `CURRENT_PROJECT_VERSION` | ✏️ build number, **+1 each upload** (ASC rejects reuse) |

Then regenerate and commit: `xcodegen generate`.

## 2. Archive & upload

**Xcode way:** open `BarcodeDeck.xcodeproj` → *Signing & Capabilities* →
select the team → *Product → Archive* → in the Organizer
*Distribute App → App Store Connect → Upload*.

**CLI way** (same result):

```bash
xcodebuild archive -project BarcodeDeck.xcodeproj -scheme BarcodeDeck \
  -archivePath build/BarcodeDeck.xcarchive
xcodebuild -exportArchive -archivePath build/BarcodeDeck.xcarchive \
  -exportPath build -exportOptionsPlist exportOptions.plist   # method = app-store
```

- [ ] Smoke-test the archive on a real device (Developer Mode on) before
      uploading: scan → present → import → export once.

## 3. App Store Connect — create the app

1. [ ] **Apps → + → New App**
      - Name: `Barcode Deck` (30 max)
      - Primary language: `English (U.S.)`
      - Bundle ID: `dev.barcodedeck.app`
      - SKU: `barcodedeck-ios`
2. [ ] **App Privacy** and export compliance are pre-wired in the bundle
      (see constants) — confirm in §5.

## 4. Version page — App Information & copy

**App Information:**

| Field | Put this |
| --- | --- |
| Subtitle (30) | `Your loyalty cards, one deck` |
| Primary category | `Utilities` |
| Secondary category | `Shopping` (or `Lifestyle`) |
| Copyright | `© ✏️ <year> <your name>` |
| Support URL | ✏️ the repo/issues URL or privacy-policy site |

**Pricing & Availability:** `Free`, all territories.

**App Privacy:** ✏️ URL of the live privacy policy (template in
[`HOW_TO_PUBLISH.md` §3](HOW_TO_PUBLISH.md#3-privacy-policy-template)).

**Version-specific text:**

- [ ] Promotional text (170 max, editable anytime):

  > Scan a card once, show it forever. No accounts, no cloud, no tracking.

- [ ] Description (paste):

  > Barcode Deck is the simplest way to carry all your shop and loyalty
  > cards.
  >
  > SCAN ONCE — Point the camera at any barcode. The value is recognized,
  > validated and saved with a name you choose.
  >
  > TAP TO SHOW — Tap a card and your phone becomes the card: the barcode
  > fills the screen at maximum brightness in its true physical size,
  > ready for any checkout scanner. Pinch to zoom if a particular reader
  > prefers it bigger or smaller.
  >
  > WORKS OFFLINE — No account, no cloud, no tracking. Your cards never
  > leave your device.
  >
  > SHARE A DECK — Export your whole deck as a single JSON file and share
  > it with family via AirDrop or Messages. Importing merges cleanly —
  > duplicates are skipped automatically.
  >
  > SCANS & RENDERS — EAN-13, UPC-A, Code 128 and Code 39 (the
  > symbologies used by loyalty programs and health cards). All other
  > linear codes are stored with their value and shown as text.

- [ ] Keywords (100 max):
  `barcode,loyalty,cards,wallet,scanner,membership,fidelity,codice,coupon,shop`
- [ ] ✏️ "What's New" release notes.

## 5. Privacy & ratings

- [ ] **App Privacy → Get Started**: "Do you or your third-party partners
      collect data from this app?" → **No**. Done — the bundled
      `PrivacyInfo.xcprivacy` matches this answer.
- [ ] **Export compliance**: nothing to declare — the Info.plist flag
      (`ITSAppUsesNonExemptEncryption = false`) answers it at upload.
- [ ] **Age rating** questionnaire: answer all; expected result **4+**
      (no user-generated content, no web content, no gambling).
- [ ] **App Review information**: paste into the notes box:

  > Barcode Deck stores barcoded shop/loyalty cards and displays them
  > full-screen for scanning at checkout. Demo: launch, tap +, scan or
  > type a value (e.g. 4006381333931), save, tap the card — the phone
  > shows the barcode full-screen. No account needed. The camera
  > permission is for barcode scanning only.

  - Contact: yourself, reachable during review. No demo account needed.

## 6. Screenshots (required device sets)

| Set | How |
| --- | --- |
| 6.9" iPhone (required) | Simulator `iPhone 16/17 Pro Max` → `xcrun simctl io <device> screenshot` |
| 6.5" iPhone (required) | Simulator `iPhone 11/13/14 Plus` |

Suggested shots (from `/screenshots/`, or capture fresh): list with a few
cards, presentation mode landscape with a barcode, add form with
validation, delete with the undo bar. The debug launch arguments
`--debug-present-demo` and `--debug-show-add` produce honest, reproducible
states — screenshots must only show what the app really does (the #1
metadata-rejection cause).

## 7. TestFlight, then submit

1. [ ] Upload lands in **TestFlight** — install on a device, re-run the
      smoke test against that build.
2. [ ] Add the build to the version page, answer the remaining export /
      IDFA prompts (IDFA: **not used**).
3. [ ] **Submit for Review.** Typical review: < 24–48 h.
- [ ] After approval: tag — `git tag ios-v1.0.1 && git push --tags`.

## Sign-off

- [ ] MARKETING_VERSION in sync with Android versionName; build number +1
- [ ] Tests green · archived from a clean checkout · device smoke test
- [ ] Copy pasted (subtitle, promo, description, keywords, review notes)
- [ ] Privacy: Data Not Collected · privacy policy URL live
- [ ] Screenshots only show real app behavior
