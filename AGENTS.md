# Clarity Flutter — Agent Guide

Flutter todo app. Local-first (Hive CE) + Supabase sync, Riverpod state.
Primary target for this session: **Windows desktop app**.

## Run on Windows (exact order)

1. `flutter pub get`
2. `Copy-Item .env.example -Destination .env` then fill keys (empty = local-only, works offline)
3. `flutter run -d windows --dart-define-from-file=.env`
4. Verify: `dart analyze` must say "No issues found"; `flutter test`

> Always pass `--dart-define-from-file=.env` — without it the build silently falls back to local-only ("Local only" sidebar footer).

- Single test: `flutter test test/<name>_test.dart` (e.g. `sync_engine_test.dart`)
- Release exe: `flutter build windows --release --dart-define-from-file=.env` → `build/windows/x64/runner/Release/Clarity.exe`
- Installer: `installer/windows/clarity.iss` via Inno `ISCC.exe` in **pwsh** (not Git Bash — MSYS mangles `/D` defines). `AppVersion` must be numeric dotted only; release workflow sanitizes tag → filename separately. Portable ZIP = `Compress-Archive build/windows/x64/runner/Release/*`.

Prereqs: Flutter 3.47+ stable, VS Build Tools, Windows 10/11 x64. `flutter config --enable-windows-desktop` once.

## Architecture (not obvious from filenames)

- Entrypoint `lib/main.dart`: main window + `quick_add` sub-window (`desktop_multi_window`, separate isolate). Main isolate owns Hive/sync/notifications; panel submits via `quick_add_submit` channel.
- `lib/core/` TaskListNotifier owns state; mutation → Hive persist → reschedule notifications → widget refresh → debounced push (1.2s). Foreground pull 15s + 5s coalesced retry, backoff to ~60s.
- `isDesktopApp` (`lib/desktop/desktop.dart`) gates tray/hotkey/`window_manager`: true on macOS/Windows/Linux only, false on web and when `FLUTTER_TEST` set. Guard new desktop code the same way.
- Hive boxes open in exactly one isolate. Background workers may only touch `SharedPreferences` + notifications — never Hive.
- `AppConfig.isConfigured` false → local-only, no login gate in debug. `release` string in `lib/core/app_config.dart` must be bumped with `pubspec.yaml` version.
- OAuth callback `com.harry.Clarity://oauth-callback`; Windows registration in `clarity.iss` (HKCU, no elevation). Don't rename without updating Supabase allow-list + macOS plist + iss.

## Conventions & gotchas

- Branches: `main` release-ready (protected), `develop-ai` active dev. Branch `feat/<x>`, `fix/<x>` off `develop-ai`. Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), imperative, explain why. See `CONTRIBUTING.md`.
- `test/` mirrors `lib/`; new logic needs unit test, new UI needs widget test where practical.
- Supabase: apply `supabase/migrations/` (`updated_at` trigger + `tasks_delete_own` DELETE RLS). Missing DELETE policy → swipe-deletes queue forever and retry.
- Never commit: `.env`, `google-services.json`, `GoogleService-Info.plist`, `*.jks`/`key.properties` — check `git status`.
- CI (`ci.yml`): `flutter pub get` → `dart analyze` → `flutter test`. Windows `release.yml` job is NOT gated on `checks` (known FakeAsync/Hive timing flake); validate exe on real Windows machine.
- Tray assets: `assets/tray/*`, `assets/logo/`; regenerate with `python tool/generate_logo_assets.py` after logo tweak.
