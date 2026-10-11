# ANDROID_TEMPLATE — publishing Barcode Deck to Google Play

A fill-in walkthrough for one release cycle. Every "→ put this" is the
exact value or copy to enter. Project constants are already filled in;
per-release values (versions, release notes) are marked ✏️.

Companion to [`HOW_TO_PUBLISH.md`](HOW_TO_PUBLISH.md) — that file explains
the *why*, this walks the *clicks*.

---

## Constants (same every release)

| Field | Value |
| --- | --- |
| Package / application ID | `dev.barcodedeck.app` |
| Min Android version | 8.0 (API 26) |
| Target API | 36 — Play requires API 36+ since Aug 31, 2026 |
| Keystore | `~/Documents/barcode-deck-upload-keystore.jks`, alias `barcodedeck-upload` |
| Signing config | `barcode-deck-android/keystore.properties` (git-ignored) |
| Play App Signing | enrolled — the upload key only signs uploads |
| Data collected | **None** (the app has no Internet permission at all) |

## 0. Before you start

- [ ] Export a JSON backup of your current deck from the installed app
      (Menu → Export JSON…) — release testing must not risk data.
- [ ] Tests green: `cd barcode-deck-android && ./gradlew testDebugUnitTest`
- [ ] Privacy policy live (URL needed twice below).
      Template text: [`HOW_TO_PUBLISH.md` §3](HOW_TO_PUBLISH.md#3-privacy-policy-template).
- [ ] `JAVA_HOME` points at a JDK 17–21 (`openjdk@21` works; the system
      JDK 27 is too new for Gradle).

## 1. ✏️ Set the version

In `barcode-deck-android/app/build.gradle.kts` → `defaultConfig`:

| Field | Put this |
| --- | --- |
| `versionCode` | ✏️ last one **+ 1** (Play rejects reused codes) |
| `versionName` | ✏️ e.g. `"1.0.1"` |

Keep iOS in sync ([`IOS_TEMPLATE.md`](IOS_TEMPLATE.md) §1).

## 2. Build the bundle

```bash
cd barcode-deck-android
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
./gradlew bundleRelease
# → app/build/outputs/bundle/release/app-release.aab
```

- [ ] Confirm the AAB is **signed**: if `keystore.properties` is missing
      the build still succeeds but the output is unsigned and Play will
      reject it.
- [ ] Smoke-test the exact artifact: `./gradlew assembleRelease` and
      `adb install -r app/build/outputs/apk/release/app-release.apk`
      on a real device. Scan → present → import → export once.

## 3. Play Console — create the app

1. [ ] **All apps → Create app**
      - App name: `Barcode Deck`
      - Default language: `English (United States)`
      - App or game: `App` · Free or paid: `Free`
2. [ ] Accept declarations; the app is neither a news nor a government app.

## 4. Store listing (Grow → Store presence → Main store listing)

| Field | Limit | Put this |
| --- | --- | --- |
| App name | 30 | `Barcode Deck` |
| Short description | 80 | `Scan once, show forever: your loyalty cards, offline. No account, no ads.` |
| Full description | 4000 | block below |

**Full description** (paste):

> Barcode Deck is the simplest way to carry all your shop and loyalty cards.
>
> SCAN ONCE — Point the camera at any barcode. The value is recognized,
> validated and saved with a name you choose.
>
> TAP TO SHOW — Tap a card and your phone becomes the card: the barcode
> fills the screen at maximum brightness in its true physical size, ready
> for any checkout scanner. Pinch to zoom if a reader prefers it bigger
> or smaller.
>
> TYPE IT IN — No barcode to scan? Enter the value manually, with a
> barcode-type selector, live format validation and check-digit checks.
>
> WORKS OFFLINE — No account, no cloud, no tracking. Your cards never
> leave your device: the app holds no network permission at all.
>
> SHARE A DECK — Export your whole deck as a single, human-readable JSON
> file and share it with family. Importing merges cleanly — duplicates
> are skipped automatically.
>
> One card less in the wallet. One app instead of twelve.

- [ ] App icon: 512×512 PNG (the launcher icon from the repo works).
- [ ] Feature graphic: 1024×500 — no text overlay needed.
- [ ] Phone screenshots: 2–8, 9:16, from `/screenshots/`
      (list, presentation, add-card, undo). At least: list + presentation.
- [ ] Save. (No tablet set required if the app doesn't claim tablet
      optimization — add the same screenshots if you opt in later.)

## 5. App content (Policy → App content)

Answer in order; the console unlocks sections as you go.

1. [ ] **Privacy policy**: ✏️ paste the URL.
2. [ ] **Ads**: `No, my app doesn't contain ads`.
3. [ ] **Data safety** — the honest answers for this app:
      - "Does your app collect or share any of the required user data
        types?" → **No**. Done — nothing else to fill.
      - Rationale you can rely on: no Internet permission, no analytics,
        no tracking; the camera only looks at barcodes on-device.
4. [ ] **Content rating** questionnaire: category `Utility`, complete all
      questions truthfully → expected rating **Everyone** (3+/PEGI 3).
5. [ ] **Target audience**: `18+` is fine (the app is not directed at
      children). Skip the children's-program review.
6. [ ] **News**: `No`. **COVID-19**: `No`. **Government**: `No`.
7. [ ] **Data deletion** (if asked): data is user-held via JSON export;
      uninstalling removes everything.

## 6. Release to Internal testing

1. [ ] **Release → Testing → Internal testing → Create new release**
2. [ ] Upload `app-release.aab`.
3. [ ] ✏️ Release notes ("What's new"), e.g. first release:

   > Initial release. Scan, type, present and share your loyalty cards —
   > fully offline.

4. [ ] Review, then **Start rollout to Internal testing** (up to 100
      testers, no review wait usually).
5. [ ] **Install from the internal link** on a real device and re-run the
      smoke test against the store build.

## 7. Promote

- [ ] Closed testing (optional, same release, add tester lists).
- [ ] **Production → Create release → reuse the AAB → review → roll out.**
      First submission triggers full review (typically 1–7 days).
- [ ] When approved: tag the commit — `git tag android-v1.0.1 && git push --tags`.

## Sign-off

- [ ] versionCode incremented and in sync with iOS marketing version
- [ ] Tests green · AAB signed · device smoke test passed
- [ ] Store listing complete (icon, graphic, screenshots, copy)
- [ ] Data Safety answered: nothing collected · Privacy policy URL live
- [ ] Release notes written · tag pushed
