# Contributing to Clarity Flutter

Thanks for picking this up — Clarity stays minimal by design, so small,
focused contributions beat big ones. This guide covers setup, workflow, and
the rules that keep `main` release-ready.

## Getting started

```sh
git clone https://github.com/hariprasad2512/clarity_flutter.git
cd clarity_flutter
flutter pub get
cp .env.example .env   # fill in your own keys; never commit this file
```

Run with your env file (without it the build silently drops to local-only):

```sh
flutter run -d macos --dart-define-from-file=.env
flutter run -d android --dart-define-from-file=.env
```

Apply the SQL in `supabase/migrations/` to your own Supabase project
(Dashboard → SQL Editor, or `supabase db push`) if you work on sync.

## Branching

- `main` — release-ready, protected by CI + PR review. Never push directly.
- `develop-ai` — active development branch. Branch feature work off it:
  `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`.
- Open PRs against `main` (or `develop-ai` for work-in-progress). Keep each
  PR to a single concern.

## Commits

Conventional commits, imperative mood, explain the "why":

```text
feat: edit sheet with quick remind presets
fix: RichText titles rendered white without DefaultTextStyle merge
chore: bump workmanager to 0.10.10
docs: rewrite README platform table
refactor: share post-write refresh in main wiring
test: cover delete-outbox shield in SyncEngine
```

## Code standards

- Dart: Effective Dart, `const` constructors where possible, business logic
  out of widgets (see `AGENTS.md` for the full per-language rules).
- Keep it minimal — Clarity rejects feature bloat. If a change adds UI,
  it must work on both macOS and Android unless there's a platform reason.
- Best-effort I/O everywhere background/foreground: never let a plugin
  failure crash the app; surface it via status or debug log instead.
- Hive boxes open in exactly one isolate. Background workers (Workmanager)
  may only touch `SharedPreferences` + local notifications.

## PR checklist

- [ ] `dart analyze` reports "No issues found".
- [ ] `flutter test` passes; new logic has unit tests, new UI behavior has
  widget tests where practical (`test/` mirrors `lib/` structure).
- [ ] No secrets committed: `.env`, `google-services.json`,
  `GoogleService-Info.plist`, `*.jks`/`key.properties` are gitignored —
  double-check `git status` before pushing.
- [ ] Migrations (if any) are idempotent and documented in the PR body.
- [ ] Screenshots for user-visible changes (drop into `docs/screenshots/`).

## Reporting issues

Include: platform + OS version, `flutter --version`, whether the build used
`--dart-define-from-file=.env`, steps to reproduce, and relevant log lines
(`flutter run -v` output or the sidebar sync status). For sync bugs, note
whether both devices share one Google account and what the sync dot showed.

## License

By contributing you agree your work lands under the repo's MIT license.
