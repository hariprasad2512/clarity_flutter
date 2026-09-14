# Clarity Flutter

A minimal, open-source (MIT) todo app for **macOS, iOS, Android, Windows, and
Web**. Capture fast, track simply, sync everywhere.

This is the cross-platform Flutter port of the native macOS
[Clarity](https://github.com/hariprasad2512/Clarity) app (SwiftUI). It keeps
the same philosophy — **local-first, minimal by design, no feature bloat** —
and obeys the same data contract (`public.tasks`, per-user RLS,
last-write-wins on `updated_at`; see the native repo's `AGENTS.md`).

## ✨ Features (to date)

- **Clean workspace** — sidebar (Today / Inbox / Done with counts) + focused
  list, search, one-line capture with calendar/clock scheduling, adaptive
  wide (≥760px) and narrow layouts, overdue highlighting.
- **Natural-language dates** — `"Pay rent tomorrow at 5pm"`, `"6.20 pm"`,
  weekdays, `tonight`, `weekend`, `in 2 hours`, `Sep 12`; detected date
  words are stripped Todoist-style.
- **Calendar scheduling** — month picker plus Today / Tomorrow / Weekend
  presets; manual picks override auto-parse.
- **Quick Add dialog** — spotlight-style capture (`Enter` saves, `Esc`
  dismisses, stays open for rapid entry).
- **Smart actionable alerts** — the task title is the notification, with
  **Mark Done** and **Remind me later** buttons (delay configurable in
  Settings, default 1 hour). Each device schedules its own alerts locally,
  so everywhere you're logged in reminds you — no push server needed.
- **Privacy-first default** — everything works offline in a local Hive
  store. No account, no tracking.

## 📊 Platform support

| Capability | macOS | iOS | Android | Windows | Web |
|---|---|---|---|---|---|
| Offline tasks, NLP dates, capture | ✅ | ✅ | ✅ | ✅ | ✅ |
| Local notifications + actions | ✅ | ✅ | ✅ | ✅ | ❌¹ |
| Google sign-in + Supabase sync | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Global hotkey / tray / widgets | 🔜 | 🔜 | 🔜 | 🔜 | — |

¹ Web has no scheduler backend in `flutter_local_notifications`; the app
runs fully otherwise.

## 🗺️ Roadmap

- **Phase 0–1** ✅ — foundation, offline core + UI, 29+ tests
- **Phase 2** ✅ — actionable local notifications
- **Phase 3** 🔜 — Supabase Auth (Google) + Postgres sync, same `public.tasks`
  schema/migrations as the native app
- **Phase 4** 🔜 — desktop extras (global hotkey, tray, launch at login)
- **Phase 5** 🔜 — home-screen widgets, release packaging per store

## 🚀 Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47+ (`flutter
  --version`)
- macOS builds: Xcode 16+. Android: Android Studio + SDK. Windows: VS Build
  Tools.

### Setup

```sh
git clone https://github.com/hariprasad2512/clarity_flutter.git
cd clarity_flutter
flutter pub get
# Cloud sync is Phase 3 — the app runs fully offline without this:
cp .env.example .env   # then fill in your Supabase URL + anon key
```

### Run

```sh
flutter run -d macos     # macOS
flutter run -d ios       # iOS simulator
flutter run -d android   # Android emulator / device
flutter run -d windows   # Windows desktop
flutter run -d chrome    # Web
```

With env defines (Phase 3): `flutter run --dart-define-from-file=.env`

### Verify

```sh
flutter test      # unit + widget tests
dart analyze      # must report "No issues found"
flutter build macos --debug
```

## 🔔 Notifications

- Permission is requested on first launch (best-effort, never blocks).
- Alerts re-register on every launch (covers reboot).
- Tapping **Mark Done** completes the task; **Remind me later** pushes it
  out by your Settings delay. Taps cold-start the app first when killed —
  actions apply on launch (Hive boxes can't open in two isolates).
- Android needs exact-alarm permission for precise due-time firing
  (requested in-app; permissions are declared in the manifest).

## 🤝 Contributing

- Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
  `test:`.
- Keep PRs focused; `flutter test` + `dart analyze` must pass.
- Never commit secrets — only `*.template.*` / `.env.example` patterns.
  Real `.env`, `google-services.json`, `GoogleService-Info.plist` and
  `SupabaseConfig.plist` are gitignored.

## 📄 License

MIT — see [LICENSE](LICENSE).
