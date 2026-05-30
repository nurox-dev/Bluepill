# Project BluePill

Project BluePill is a Flutter + Supabase life operating system. It connects a user's mission, tasks, habits, calendar, AI check-ins, daily streaks, progress analytics, and Agent conversations into one dashboard.

## What It Does

- Flutter web app and Linux desktop app with Supabase Auth.
- Mission, goals, tasks, habits, check-ins, progress, calendar, and settings screens.
- AI check-ins that extract structured progress from natural language.
- Daily AI check-in streak tracking with current streak, best streak, and last check-in date.
- Dashboard and Progress views for life score, focus, completion rates, blockers, habit streaks, and check-in streaks.
- Agent chat with stored Project BluePill context and attachment metadata.
- Google Calendar / Tasks browser OAuth integration.
- Firebase Hosting for the Flutter web build.
- FlutterFire web configuration through `firebase_core`.
- Supabase Edge Functions for production agent API entry points.
- FastAPI worker for queued agent jobs, tool calls, audit logs, and notifications.

## Architecture

```text
Flutter App
  -> Supabase Auth
  -> Supabase Edge Functions
  -> Supabase Postgres
  -> Upstash QStash
  -> FastAPI Worker
  -> OpenAI Agents SDK
  -> Tools: Supabase, Google, Firebase
  -> Audit Logs + Realtime Updates
  -> Flutter UI
```

Full architecture: [docs/architecture.md](docs/architecture.md)

## Repository

```text
flutter/                     Flutter app root
flutter/lib/                 UI and client-safe app services
flutter/lib/services/        Supabase, AI, context, calendar, and agent clients
flutter/lib/firebase_options.dart
                             Generated FlutterFire web config
firebase.json                Firebase Hosting config for Flutter web
.firebaserc                  Firebase project alias
supabase/schema.sql          Current database schema source
supabase/migrations/         Supabase migration files
supabase/functions/          Edge Functions API gateway
worker/app/                  FastAPI worker, jobs, agent boundary, and tools
docs/                        Architecture, hosting, environment, and checklist docs
```

## Documentation

- [docs/architecture.md](docs/architecture.md): production architecture and responsibility boundaries.
- [docs/app-theme.md](docs/app-theme.md): Material 3 Expressive theme, brand palette, and UI usage rules.
- [docs/hosting.md](docs/hosting.md): how each service runs locally and in production.
- [docs/environment.md](docs/environment.md): public env values and backend secrets.
- [docs/project-links.md](docs/project-links.md): production URLs, dashboards, consoles, and project IDs.
- [docs/deployment-checklist.md](docs/deployment-checklist.md): what is done and what is still pending.

## Project Links

Quick links:

- Web app: https://project-bluepill.web.app
- Worker health: https://project-bluepill-worker.onrender.com/healthz
- GitHub: https://github.com/anishahsarvatraasti/ProjectBluepill
- Supabase dashboard: https://supabase.com/dashboard/project/qhunsphxuzmheduacull
- Firebase console: https://console.firebase.google.com/project/project-bluepill/overview
- Google Cloud console: https://console.cloud.google.com/welcome?project=project-bluepill&supportedpurview=project,organizationId,folder
- Render worker: https://dashboard.render.com/web/srv-d82jkml0lvsc738hb37g
- QStash console: https://console.upstash.com/qstash

Full dashboard index: [docs/project-links.md](docs/project-links.md)

## Local App

Install Flutter packages:

```bash
cd flutter
flutter pub get
```

Create local Flutter env:

```bash
cp .env.example .env
```

Run web locally on the required port:

```bash
flutter run -d web-server --web-hostname localhost --web-port 3000
```

Open:

```text
http://localhost:3000
```

Run the native Linux app:

```bash
flutter run -d linux
```

Build the native Linux release bundle:

```bash
flutter build linux --release
```

Output:

```text
flutter/build/linux/x64/release/bundle/project_bluepill
```

## Firebase

The Firebase project is:

```text
Project ID: project-bluepill
Hosting URL: https://project-bluepill.web.app
```

FlutterFire is configured for the Flutter web target and generates:

```text
flutter/lib/firebase_options.dart
flutter/firebase.json
```

Re-run FlutterFire config from the Flutter project root:

```bash
cd flutter
flutterfire configure --project=project-bluepill
```

Current official `firebase_core` support in this workspace does not include a Linux plugin. The Linux app therefore skips Firebase initialization and continues to use Supabase for auth and data.

Deploy the Flutter web build to Firebase Hosting from the repo root:

```bash
cd flutter
flutter build web --release
cd ..
firebase deploy --only hosting --project project-bluepill
```

For production Google/Supabase OAuth, set
`AUTH_REDIRECT_ORIGIN=https://project-bluepill.web.app` in `flutter/.env`
before building, and add that same URL to Supabase Auth URL Configuration.

## Supabase

The repo is set up for the Supabase cloud project:

```text
Project: Project BluePill
Ref: qhunsphxuzmheduacull
Region: Southeast Asia, Singapore
```

Useful commands:

```bash
supabase projects list
supabase functions list
supabase migration list
```

Deploy Edge Functions:

```bash
supabase functions deploy agent-chat
supabase functions deploy approve-action
supabase functions deploy schedule-job
```

Push migrations only when ready:

```bash
supabase db push
```

## Worker

Run locally:

```bash
cd worker
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Production host: Render Web Service. See [docs/hosting.md](docs/hosting.md).

## Daily AI Check-In Streak

The streak system is backed by `ai_checkin_streaks`.

Rules:

- First AI check-in starts a 1-day streak.
- Another check-in on the same day does not double count.
- A check-in on the next day increments the streak.
- Missing a day resets the current streak to 1.
- Best streak is preserved.

The app updates the streak after saving a check-in and shows it on the Check-In, Dashboard, and Progress screens.

## Tests

```bash
cd flutter
flutter analyze
flutter test
flutter build linux --release
```

## Secrets

Flutter only gets public/client-safe values in `flutter/.env`.

Firebase client config in `flutter/lib/firebase_options.dart` is public client configuration, not a backend secret.

Never put these in Flutter:

```text
SUPABASE_SERVICE_ROLE_KEY
QSTASH_TOKEN
WORKER_SHARED_SECRET
OPENAI_API_KEY
OPENROUTER_API_KEY
```

Use [docs/environment.md](docs/environment.md) for where each value belongs.
