# Privacy Policy — Clarity

**Effective date:** 17 September 2026
**Contact:** harrypsd25@gmail.com

Clarity ("the app") is a minimal, offline-first todo app. This policy
explains what data the app handles, where it goes, and your rights.
The short version: **your tasks live on your device; nothing leaves it
unless you sign in, and then only to sync your own tasks.**

## 1. How Clarity works

- **Without an account (local-only mode):** everything — tasks, due
  dates, settings — is stored on your device using local storage
  (Hive, SharedPreferences). No account, no tracking, no network
  calls to our servers, because there are no servers of ours.
- **With Google sign-in (cloud sync):** the app syncs your tasks
  through Supabase (database + authentication) so multiple devices
  stay aligned.

## 2. Data we process

### a) On your device only (never transmitted by us)

- Task titles, due dates, completion state, creation/update times.
- App settings (e.g. "Remind me later" delay, offline mode).
- Notification schedules. Reminders are computed and fired
  **entirely on-device** by your OS; reminder content is never sent
  to any server.

### b) Sent to Supabase, only when you sign in

- Account identifiers: your Supabase user ID and the email address
  from your Google account.
- Task rows for sync: task ID, title, due date, completion flag,
  creation/update timestamps (`id`, `user_id`, `title`, `due_at`,
  `is_completed`, `created_at`, `updated_at`).
- Access is restricted per-user (row-level security): you can only
  read and write your own rows.

### c) Sent to Google, only when you sign in

- Google OAuth sign-in (email scope) to authenticate you. Governed
  additionally by Google's Privacy Policy.

## 3. What we never collect

- No location, contacts, photos, microphone, or camera data.
- No advertising identifiers; no ads; no sale or rental of data.
- No third-party analytics or crash-reporting SDKs. The app contains
  none.

## 4. Permissions and why (Android)

- **Notifications** (`POST_NOTIFICATIONS`) — to show due-task alerts.
- **Alarms & reminders** (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`)
  — to fire reminders at exact due times; falls back to inexact
  scheduling if denied.
- **Run at startup** (`RECEIVE_BOOT_COMPLETED`) — to restore
  reminders after reboot/update.
- **Vibrate** (`VIBRATE`) — alert haptics.

## 5. Data retention and deletion

- Local data is deleted when you uninstall the app.
- Synced data lives in Supabase until you delete your account or
  request deletion: email **harrypsd25@gmail.com** and we will delete
  your rows. Deleting the app alone does not delete server copies —
  sign in once more or contact us first if you want them gone.

## 6. Security

- Sync traffic is encrypted in transit (HTTPS). Server rows are
  isolated per user. No method is 100% secure, but the design
  minimises exposure: no account is needed at all, and sync carries
  only your task list.

## 7. Children

Clarity is a general productivity utility intended for users aged
13 and older. It is not directed at children and contains no
age-inappropriate content.

## 8. Changes

Material changes will be reflected here with a new effective date.
Continued use after changes means acceptance.

## 9. Contact

Questions or deletion requests: **harrypsd25@gmail.com**.
