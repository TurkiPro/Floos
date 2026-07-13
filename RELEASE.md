# Releasing فلوس (Floos)

Everything in the repo is already wired for automated releases. What's left is
the part only you can do: create the developer accounts, generate the signing
keys, and fill in the store listings.

- **App ID (both platforms):** `com.turkisecurity.floos`
- **Release trigger:** pushing a tag `v*` (e.g. `v1.0.1`)
- **Android target:** Play Console → *Internal testing*
- **iOS target:** App Store Connect → *TestFlight*

---

## What the pipeline already does

| Workflow | Trigger | What it does |
|---|---|---|
| `.github/workflows/ci.yml` | every push / PR | `dart format` check, codegen, `flutter analyze`, `flutter test`, and a full **release AAB build** (debug-signed) to prove the native config assembles |
| `.github/workflows/release.yml` | tag `v*` | Builds a signed AAB + IPA, uploads them to Play internal testing and TestFlight, and attaches both to a GitHub Release |

The release workflow is **gated on secrets**. With no secrets set it still runs
and produces installable artifacts — it just skips the store uploads. Add the
secrets and the uploads light up with no workflow changes.

Version numbers are derived automatically: the tag is the version name
(`v1.2.3` → `1.2.3`) and the GitHub run number is the build number (which must
strictly increase for every store upload, so never reuse one).

---

## Before your first submission

### 0. App icon — done ✅

Generated from `assets/icon/icon.png` (1024×1024, RGB, no alpha) into both
platforms' icon sets. Android gets an adaptive icon (`#1C1C20` background +
the artwork inset into the launcher safe zone, so no mask can clip the coin);
iOS gets the flat, alpha-free square Apple requires.

To change the artwork, replace `assets/icon/icon.png` and re-run:

```bash
dart run flutter_launcher_icons
```

### 0b. Privacy policy + contact email — done ✅

- Policy live at <https://floos.turkisecurity.com/privacy.html> (Cloudflare Pages),
  bilingual AR/EN, verified returning 200.
- `privacy@turkisecurity.com` routes to `turki.security@gmail.com` via Cloudflare
  Email Routing (MX records confirmed live).

Both go in the store listings — see `STORE_LISTING.md`.

### 1. Google Play ($25, one-time)

1. Sign up: <https://play.google.com/console> → pay the $25 one-time fee.
   Identity verification takes a few days — start this first.
2. **Create app** → name "فلوس", language Arabic, *App*, *Free*.
3. Generate the upload keystore (keep this file forever — losing it means you
   can never update the app):

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

4. Base64-encode it for GitHub:

   ```bash
   base64 -w0 upload-keystore.jks > keystore.b64      # Linux
   certutil -encode upload-keystore.jks keystore.b64  # Windows
   ```

5. Create a **service account** for automated uploads:
   Play Console → *Setup → API access* → link a Google Cloud project → create a
   service account → grant it **Release manager** → download the JSON key.
6. **Upload the very first AAB by hand.** The Play API refuses to publish to an
   app that has never had a release, so the automation can't do release #1.
   Download the AAB artifact from a CI run, or build locally, and upload it in
   the console once. Every release after that is automated.

### 2. Apple ($99/year)

1. Enroll: <https://developer.apple.com/programs/> ($99/yr, renews annually).
2. App Store Connect → **My Apps → +** → New App → bundle ID
   `com.turkisecurity.floos`, name "فلوس", primary language Arabic.
3. Create an **App Store Connect API key**: Users and Access → *Integrations →
   App Store Connect API* → generate a key with **App Manager** role. Download
   the `.p8` (you only get one chance) and note the *Key ID* and *Issuer ID*.
4. Create an **iOS Distribution certificate** in the Developer portal, export it
   from Keychain as a `.p12` with a password, and base64-encode it.
5. Your **Team ID** is in the top-right of the Developer portal membership page.

---

## GitHub secrets

`Settings → Secrets and variables → Actions → New repository secret`.

### Android

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contents of `keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password from `keytool` |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password from `keytool` |
| `PLAY_SERVICE_ACCOUNT_JSON` | the whole service-account JSON file, pasted |

### iOS

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPSTORE_ISSUER_ID` | Issuer ID from App Store Connect API |
| `APPSTORE_KEY_ID` | Key ID of the `.p8` |
| `APPSTORE_PRIVATE_KEY` | full contents of the `.p8` file |
| `IOS_DIST_CERT_P12` | base64 of the distribution `.p12` |
| `IOS_DIST_CERT_PASSWORD` | password you set when exporting the `.p12` |

Nothing sensitive is committed: `android/key.properties`, `*.jks`, `*.p12` and
`*.p8` are all in `.gitignore`, and CI recreates them from these secrets at
build time.

---

## Store listing content you still have to write

**All of the copy and every form answer is written out in `STORE_LISTING.md`** —
app names, descriptions, keywords, the Data safety answers, the privacy nutrition
labels, and the content-rating answers. Paste them straight in.

The one thing still missing is **screenshots**, which need a real device,
emulator or simulator (a resized desktop window won't satisfy Apple's exact
pixel dimensions). `STORE_LISTING.md` lists the required sizes and which five
screens to shoot.

On permissions: the app declares only `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE` and `USE_BIOMETRIC`. Nothing restricted, so
there is no permissions declaration form to fill in.

---

## Cutting a release

```bash
# make sure main is green in CI first
git tag v1.0.0
git push origin v1.0.0
```

That builds both platforms, uploads to Play internal testing + TestFlight, and
attaches the AAB and IPA to a GitHub Release.

To promote to production, use the Play Console / App Store Connect UI — the
pipeline deliberately stops at the internal/TestFlight gate so a bad build can
never go straight to users.
