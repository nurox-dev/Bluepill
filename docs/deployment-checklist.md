# Project BluePill Deployment Checklist

Only tracks what is done and what is still pending.

Production URLs, dashboards, and provider consoles are listed in [project-links.md](project-links.md).

## Done

| Item | Status |
| --- | --- |
| Supabase CLI installed | [x] Done |
| Supabase login completed | [x] Done |
| Repo connected to Supabase cloud project through CLI | [x] Done |
| Supabase cloud project `Project BluePill` created | [x] Done |
| Supabase project ref `qhunsphxuzmheduacull` confirmed | [x] Done |
| Supabase Edge Functions deployed | [x] Done |
| Flutter local port set to `localhost:3000` | [x] Done |
| Supabase local auth URL set to `localhost:3000` | [x] Done |
| Initial database migration file exists | [x] Done |
| Database push command completed against Supabase cloud | [x] Done |
| AI check-in streak migration file exists | [x] Done |
| AI check-in streak migration pushed to Supabase cloud | [x] Done |
| Worker can run locally | [x] Done |
| Google OAuth local origin added | [x] Done |
| Firebase CLI available through user-local install | [x] Done |
| FlutterFire CLI installed | [x] Done |
| Firebase project `project-bluepill` configured | [x] Done |
| FlutterFire web app registered | [x] Done |
| `flutter/lib/firebase_options.dart` generated | [x] Done |
| Firebase Hosting config exists | [x] Done |
| Flutter web production build completed | [x] Done |
| Flutter web hosted on Firebase Hosting | [x] Done |
| `AUTH_REDIRECT_ORIGIN` set to production frontend URL before web build | [x] Done |
| Production domain added to Supabase Auth redirects | [x] Done |
| Native Linux release build completed | [x] Done |
| Linux release tarball created | [x] Done |
| FastAPI worker hosted on Render Web Service | [x] Done |
| Worker environment values added in Render | [x] Done |
| Upstash QStash token configured | [x] Done |
| `QSTASH_URL` set to US region in Supabase secrets | [x] Done |
| `QSTASH_TOKEN` set in Supabase secrets | [x] Done |
| `WORKER_BASE_URL` set in Supabase secrets | [x] Done |
| `WORKER_SHARED_SECRET` set in Supabase and Render | [x] Done |
| Production model provider env values added | [x] Done |
| Flutter web redeployed with production FastAPI worker URL | [x] Done |
| Full production agent flow tested | [x] Done |

## Pending

| Item | Status |
| --- | --- |
| Add production domain to Google OAuth | [ ] Pending |
| Finish Firebase push notification setup | [ ] Pending |
| Add native Firebase support if a Linux-capable Firebase plugin is adopted | [ ] Pending |
