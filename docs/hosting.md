# Project BluePill Hosting

Reference: `docs/architecture.md`

This file only explains how each part runs locally and how it should run in production. Status lives in `docs/deployment-checklist.md`.

Dashboard and console links live in [project-links.md](project-links.md).

## Flutter App

### Local

Web:

```bash
cd flutter
flutter run -d web-server --web-hostname localhost --web-port 3000
```

Use `http://localhost:3000` for local development.

Linux desktop:

```bash
cd flutter
flutter run -d linux
```

### Production

Firebase Hosting serves the Flutter web build for:

```text
Project ID: project-bluepill
Hosting URL: https://project-bluepill.web.app
```

Build the Flutter web release:

```bash
cd flutter
flutter build web --release
```

The build output is:

```text
flutter/build/web
```

Deploy from the repo root:

```bash
firebase deploy --only hosting --project project-bluepill
```

If `firebase` is not on `PATH`, install the Firebase CLI into a user-local prefix:

```bash
npm install -g --prefix "$HOME/.local" firebase-tools
export PATH="$HOME/.local/bin:$PATH"
```

The repo root [firebase.json](../firebase.json) points Hosting at `flutter/build/web`, keeps Flutter entry assets on `no-cache`, deploys the Flutter `.env` asset, and rewrites deep links to `index.html`.

### FlutterFire

Install the FlutterFire CLI once:

```bash
dart pub global activate flutterfire_cli
```

Make sure Dart global executables are on `PATH`:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Configure Firebase from the Flutter project root:

```bash
cd flutter
flutterfire configure --project=project-bluepill
```

Generated files:

```text
flutter/lib/firebase_options.dart
flutter/firebase.json
```

The app initializes Firebase on web through `firebase_core`. Current official `firebase_core` support in this workspace does not include a Linux plugin, so the native Linux app skips Firebase initialization and uses Supabase for auth and data.

### Linux Release

Build the native Linux release:

```bash
cd flutter
flutter build linux --release
```

Run the bundle:

```bash
cd flutter/build/linux/x64/release/bundle
./project_bluepill
```

Package the bundle:

```bash
cd flutter
tar -C build/linux/x64/release -czf build/linux/x64/release/project_bluepill_linux_x64.tar.gz bundle
```

Output:

```text
flutter/build/linux/x64/release/bundle/project_bluepill
flutter/build/linux/x64/release/project_bluepill_linux_x64.tar.gz
```

## Supabase Project

### Local

```bash
supabase login
supabase link --project-ref qhunsphxuzmheduacull
```

Optional local Supabase stack:

```bash
supabase start
```

Local Supabase URLs:

```text
API:    http://127.0.0.1:54321
Studio: http://127.0.0.1:54323
DB:     postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

### Production

Use the existing Supabase cloud project:

```text
Name: Project BluePill
Ref: qhunsphxuzmheduacull
Region: Southeast Asia, Singapore
Dashboard: https://supabase.com/dashboard/project/qhunsphxuzmheduacull
```

Check the connected project:

```bash
supabase projects list
```

## Supabase Edge Functions

### Local

Keep source code in:

```text
supabase/functions/
supabase/functions/_shared/
```

Functions:

```text
agent-chat
approve-action
schedule-job
```

### Production

Deploy functions:

```bash
supabase functions deploy agent-chat
supabase functions deploy approve-action
supabase functions deploy schedule-job
```

Check deployed functions:

```bash
supabase functions list
```

## Supabase Database, Storage, Realtime

### Local

Keep schema and seed files in:

```text
supabase/schema.sql
supabase/migrations/
supabase/seed.sql
```

Check migration state:

```bash
supabase migration list
```

### Production

Push migrations only when the schema is ready:

```bash
supabase db push
```

`supabase db push` changes the remote database.

## FastAPI Worker

### Local

```bash
cd worker
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Check:

```bash
curl http://localhost:8000/healthz
```

### Production

Host on Render as a **Web Service**.

Render settings:

```text
Service type: Web Service
Root directory: worker
Runtime: Python
Build command: pip install -r requirements.txt
Start command: uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Production endpoints:

```text
GET  https://project-bluepill-worker.onrender.com/healthz
POST https://project-bluepill-worker.onrender.com/agent/chat
POST https://project-bluepill-worker.onrender.com/jobs/agent-run
POST https://project-bluepill-worker.onrender.com/jobs/scheduled-job
GET  https://project-bluepill-worker.onrender.com/cron/jobs
POST https://project-bluepill-worker.onrender.com/cron/jobs
PATCH https://project-bluepill-worker.onrender.com/cron/jobs/{job_id}
GET https://project-bluepill-worker.onrender.com/cron/jobs/{job_id}/executions
```

The `/agent/chat` endpoint requires Supabase JWT authentication via the Authorization header.

## QStash

### Local

No local hosting is needed. Local development can call the worker directly.

### Production

Create an Upstash QStash project, then set the token in Supabase:

```bash
supabase secrets set \
  QSTASH_URL="https://qstash-us-east-1.upstash.io" \
  QSTASH_TOKEN="..."
```

QStash targets:

```text
POST https://project-bluepill-worker.onrender.com/jobs/agent-run
POST https://project-bluepill-worker.onrender.com/jobs/scheduled-job
```

## OpenAI / Model Provider

### Local

Add model provider env values to the local worker environment.

```text
AI_PROVIDER=openrouter
OPENAI_API_KEY=...
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4o-mini
OPENROUTER_API_KEY=...
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=openrouter/free
OPENROUTER_SITE_URL=https://project-bluepill.web.app
OPENROUTER_APP_NAME=Project BluePill
```

Keep model keys out of Flutter.

### Production

Add model provider env values in Render.

```text
AI_PROVIDER=openrouter
OPENAI_API_KEY=...
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4o-mini
OPENROUTER_API_KEY=...
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=openrouter/free
OPENROUTER_SITE_URL=https://project-bluepill.web.app
OPENROUTER_APP_NAME=Project BluePill
```

## Google Calendar / Tasks

### Local

Add this Google OAuth JavaScript origin:

```text
http://localhost:3000
```

### Production

Add the production frontend domain in Google Cloud OAuth:

```text
https://project-bluepill.web.app
```

Set the same frontend URL in `flutter/.env` before `flutter build web`:

```text
AUTH_REDIRECT_ORIGIN=https://project-bluepill.web.app
```

Also add the same frontend URL to Supabase Auth URL Configuration:

```text
Site URL: https://project-bluepill.web.app
Redirect URLs: https://project-bluepill.web.app/**
```
