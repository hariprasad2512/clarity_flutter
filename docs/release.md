# Release guide — Play Store + Homebrew tap

## Versioning

- `pubspec.yaml` is the source of truth (`1.0.0+1` = versionName `1.0.0`, versionCode `1`).
- Bump `+N` on **every** Play upload; bump `1.0.x` on user-visible changes.
- Tag releases as `v<versionName>` (e.g. `v1.0.0`); CI attaches artifacts to the GitHub Release.

## Android signing fingerprints (package `com.harry.Clarity`)

> Public fingerprints only — safe to commit. Never commit keystores, passwords, or `.env`.
> Extracted 2026-09-18. Play-signing cert verified via
> `apksigner verify --print-certs` on the Play-signed universal APK.

| Key | SHA-1 | SHA-256 |
|---|---|---|
| Play App Signing (final on-device key) | `50:06:CC:66:8E:66:1C:4A:22:9D:36:2A:79:F6:F2:AD:97:33:A7:7B` | `D9:08:C7:65:FD:51:D2:38:D3:60:03:0E:CF:15:25:53:3E:DD:DF:58:81:19:05:D5:1C:55:21:33:E3:B3:6A:22` |
| Upload (`android/clarity-release.jks`, alias `clarity`) | `D1:4E:B3:A4:52:EB:AD:95:B2:3C:70:13:C8:2A:2C:42:E9:0F:4A:52` | `D7:B3:FC:90:CD:27:95:53:44:FB:50:E8:EF:3F:64:A4:2B:EC:F0:15:7A:BC:77:29:3E:56:03:A5:49:42:E2:3C` |
| Debug (`~/.android/debug.keystore`) | `E4:FC:7D:E8:60:10:B4:73:56:35:AE:27:B1:8C:6B:04:01:00:8C:3F` | `AA:84:D9:8F:05:40:08:CC:1A:19:EB:5B:C5:41:C7:B4:4E:69:8D:0F:6E:A9:56:00:EF:2F:93:96:67:D5:9F:37` |

Each fingerprint needs a matching Android OAuth client in Google Cloud Console
(project `652253206799`, same as `GOOGLE_WEB_CLIENT_ID`), otherwise release
builds fail with `[16] Account reauth failed`. Re-verify Play fingerprint after
any Play signing key upgrade via:
`~/Library/Android/sdk/build-tools/<ver>/apksigner verify --print-certs signed.apk`.

## GitHub secrets (Settings → Secrets → Actions)

| Secret | Source |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i android/clarity-release.jks` (local, gitignored — back up offline) |
| `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` | `android/key.properties` (gitignored) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID` | `.env` (gitignored) |
| `GOOGLE_IOS_CLIENT_ID` (optional) | `.env` |
| `GOOGLE_SERVICES_JSON` (optional, base64) | Google Cloud Console, only if Android Google sign-in needs it |

Missing `.env` secrets → CI builds local-only (mirrors `.env.example`).
Missing keystore secrets → AAB uses debug keys (**not for Play**).

## Android → Play Store (first release)

1. Local check:
   ```sh
   flutter pub get
   flutter test && dart analyze
   flutter build appbundle --release --dart-define-from-file=.env
   # → build/app/outputs/bundle/release/app-release.aab
   ```
2. Play Console (one-time, manual):
   - Pay $25 fee → **Create app**, package `com.harry.Clarity` (**immutable** — uppercase `C` kept deliberately), name `Clarity`.
   - Enroll in **Play App Signing**; keep `android/clarity-release.jks` (upload key) backed up.
   - Setup → App integrity: copy **App signing SHA-1** (final on-device key) + **Upload SHA-1**.
   - Google Cloud Console → APIs & Services → Credentials (same project as `GOOGLE_WEB_CLIENT_ID`):
     Android OAuth client for `com.harry.Clarity` for **each** SHA-1: debug, upload, Play-signing.
     Without the Play-signing entry, release builds fail with `[16] Account reauth failed`.
     Get local SHAs via: `keytool -list -v -keystore android/clarity-release.jks -alias clarity`
     and `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`.
   - Supabase Dashboard → Auth → Google provider: enabled with Web client ID + secret.
   - OAuth consent screen: if Testing mode, add internal-tester emails under Test users.
   - Privacy policy URL (required — Google sign-in + Supabase sync collect data).
   - **Data Safety**: declare account IDs/email (Google Auth) + task content stored on Supabase.
   - **Exact alarms**: manifest requests `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — justify as reminder use-case in the declaration, or switch to inexact scheduling to dodge review friction.
   - Store listing: 512px icon, 1024×500 feature graphic, 2+ phone screenshots, descriptions, category, contact email.
3. Upload the AAB to **Internal testing** → Closed → Production. First review takes hours–days.
4. CI: push tag `v1.0.0` → `release.yml` builds + attaches `dist/Clarity-1.0.0-android.aab` to the GitHub Release. (Direct Play upload via service account is a follow-up; Console upload is fine for v1.)

## macOS → Homebrew tap (unsigned)

No paid Apple Developer ID → builds are **unsigned**. Gatekeeper will quarantine the app; this is expected and documented.

1. Local check:
   ```sh
   flutter build macos --release --dart-define-from-file=.env
   ditto -c -k --keepParent build/macos/Build/Products/Release/Clarity.app dist/Clarity-1.0.0-macos.zip
   shasum -a 256 dist/Clarity-1.0.0-macos.zip
   ```
2. CI does the above automatically on tag push and attaches the ZIP + `.sha256` to the GitHub Release.
3. Personal tap (one-time, manual):
   ```sh
   # new repo github.com/hariprasad2512/homebrew-clarity, file Casks/clarity.rb
   cp homebrew/Casks/clarity.rb <tap-repo>/Casks/clarity.rb
   # set version + real sha256 from the GitHub Release, commit, push
   brew tap hariprasad2512/clarity
   brew install --cask hariprasad2512/clarity/clarity-flutter
   ```
4. Per release: update `version` + `sha256` in the tap's `clarity-flutter.rb`.
5. Users on first launch: Finder → right-click Clarity.app → Open → Open
   (one-time Gatekeeper approval for the unsigned build; then launches
   normally). CLI equivalent: `xattr -d com.apple.quarantine /Applications/Clarity.app`.
6. Future path to official `homebrew-cask` requires a paid Developer ID (signed + notarized), notable usage, and upstream review.

## Quick reference

```sh
git tag v1.0.0 && git push origin v1.0.0   # triggers release.yml
brew tap hariprasad2512/clarity && brew install --cask --no-quarantine clarity
```
