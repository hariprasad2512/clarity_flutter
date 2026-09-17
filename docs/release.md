# Release guide — Play Store + Homebrew tap

## Versioning

- `pubspec.yaml` is the source of truth (`1.0.0+1` = versionName `1.0.0`, versionCode `1`).
- Bump `+N` on **every** Play upload; bump `1.0.x` on user-visible changes.
- Tag releases as `v<versionName>` (e.g. `v1.0.0`); CI attaches artifacts to the GitHub Release.

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
