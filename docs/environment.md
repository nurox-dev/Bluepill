# Project BluePill Environment

Environment values are grouped by where they belong. Flutter gets only public client values. Backend secrets stay in Supabase Edge Function secrets or Render.

Dashboard and console links are collected in [project-links.md](project-links.md).

## Supabase Project

```text
Project: Project BluePill
Project ref: qhunsphxuzmheduacull
Region: Southeast Asia, Singapore
Dashboard: https://supabase.com/dashboard/project/qhunsphxuzmheduacull
```

CLI connection:

```bash
supabase login
supabase link --project-ref qhunsphxuzmheduacull
```

## Flutter Public Env

File:

```text
flutter/.env
```

Allowed values:

```text
SUPABASE_URL=https://qhunsphxuzmheduacull.supabase.co
SUPABASE_ANON_KEY=...
GOOGLE_OAUTH_CLIENT_ID=...
FASTAPI_BASE_URL=https://project-bluepill-worker.onrender.com
```

Flutter bundles this file into web and Linux builds as an app asset. Only put client-safe public values here.

The app also accepts public build-time fallbacks:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="https://qhunsphxuzmheduacull.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="..." \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID="..." \
  --dart-define=AUTH_REDIRECT_ORIGIN="https://project-bluepill.web.app"
```

Never put backend secrets in Flutter.

## Firebase Flutter Client Config

Firebase project:

```text
Project ID: project-bluepill
Hosting URL: https://project-bluepill.web.app
```

FlutterFire-generated files:

```text
flutter/lib/firebase_options.dart
flutter/firebase.json
```

`firebase_options.dart` contains public Firebase client config. It is not a service account and does not contain backend secrets.

Current FlutterFire config covers the web target. The native Linux app does not initialize Firebase because the installed official `firebase_core` package does not provide a Linux plugin in this workspace.

## Supabase Edge Function Secrets

```bash
supabase secrets set \
  SUPABASE_URL="https://qhunsphxuzmheduacull.supabase.co" \
  SUPABASE_ANON_KEY="..." \
  SUPABASE_SERVICE_ROLE_KEY="..." \
  QSTASH_URL="https://qstash-us-east-1.upstash.io" \
  QSTASH_TOKEN="..." \
  WORKER_BASE_URL="https://project-bluepill-worker.onrender.com" \
  WORKER_SHARED_SECRET="..."
```

Check:

```bash
supabase secrets list
```

## Render Worker Env

```text
SUPABASE_URL=https://qhunsphxuzmheduacull.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
WORKER_SHARED_SECRET=...
AI_PROVIDER=openrouter
OPENAI_API_KEY=...
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4o-mini
OPENROUTER_API_KEY=...
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=openrouter/free
OPENROUTER_SITE_URL=https://project-bluepill.web.app
OPENROUTER_APP_NAME=Project BluePill
CRON_SCHEDULER_ENABLED=true
CRON_SCHEDULER_INTERVAL_SECONDS=30
CRON_SCHEDULER_BATCH_SIZE=10
CRON_SCHEDULER_LOCK_TTL_SECONDS=600
```

## Google OAuth

Local JavaScript origin:

```text
http://localhost:3000
```

Production JavaScript origin:

```text
https://project-bluepill.web.app
```

Set the Flutter web OAuth redirect origin before deploying:

```text
AUTH_REDIRECT_ORIGIN=https://project-bluepill.web.app
```

Also add the production frontend URL to Supabase Auth URL Configuration:

```text
Site URL: https://project-bluepill.web.app
Redirect URLs: https://project-bluepill.web.app/**
```
