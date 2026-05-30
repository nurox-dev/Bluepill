# Project BluePill Links

Use this as the quick index for production URLs, dashboards, consoles, and provider settings. Do not paste secret values into docs, issues, screenshots, or support tickets.

## Production URLs

| Area | Link |
| --- | --- |
| Web app | https://project-bluepill.web.app |
| FastAPI worker | https://project-bluepill-worker.onrender.com |
| Worker health check | https://project-bluepill-worker.onrender.com/healthz |
| Supabase API | https://qhunsphxuzmheduacull.supabase.co |
| QStash publish endpoint | https://qstash-us-east-1.upstash.io |

## Dashboards

| Service | Dashboard |
| --- | --- |
| GitHub repo | https://github.com/anishahsarvatraasti/ProjectBluepill |
| GitHub commits | https://github.com/anishahsarvatraasti/ProjectBluepill/commits/main |
| Render worker service | https://dashboard.render.com/web/srv-d82jkml0lvsc738hb37g |
| Supabase project | https://supabase.com/dashboard/project/qhunsphxuzmheduacull |
| Supabase Edge Functions | https://supabase.com/dashboard/project/qhunsphxuzmheduacull/functions |
| Supabase Auth URL config | https://supabase.com/dashboard/project/qhunsphxuzmheduacull/auth/url-configuration |
| Supabase database | https://supabase.com/dashboard/project/qhunsphxuzmheduacull/editor |
| Firebase project overview | https://console.firebase.google.com/project/project-bluepill/overview |
| Firebase Hosting | https://console.firebase.google.com/project/project-bluepill/hosting/sites |
| Firebase project settings | https://console.firebase.google.com/project/project-bluepill/settings/general |
| Google Cloud project | https://console.cloud.google.com/welcome?project=project-bluepill&supportedpurview=project,organizationId,folder |
| Google OAuth credentials | https://console.cloud.google.com/apis/credentials?project=project-bluepill |
| Google OAuth consent screen | https://console.cloud.google.com/apis/credentials/consent?project=project-bluepill |
| Upstash QStash | https://console.upstash.com/qstash |
| OpenRouter keys | https://openrouter.ai/settings/keys |
| OpenRouter integrations | https://openrouter.ai/settings/integrations |
| OpenRouter activity | https://openrouter.ai/activity |
| OpenAI platform usage | https://platform.openai.com/usage |
| OpenAI billing | https://platform.openai.com/settings/organization/billing/overview |

## Project IDs

| Service | Value |
| --- | --- |
| GitHub repository | `anishahsarvatraasti/ProjectBluepill` |
| Supabase project name | `Project BluePill` |
| Supabase project ref | `qhunsphxuzmheduacull` |
| Supabase region | `ap-southeast-1` |
| Firebase project ID | `project-bluepill` |
| Firebase project number | `22904940444` |
| Firebase Hosting site | `project-bluepill` |
| Google Cloud project ID | `project-bluepill` |
| Render service name | `project-bluepill-worker` |
| Render service ID | `srv-d82jkml0lvsc738hb37g` |
| Render region | `singapore` |
| Render branch | `main` |
| QStash region endpoint | `https://qstash-us-east-1.upstash.io` |
| Worker model provider | `openrouter` |
| Worker model | `openrouter/free` |

## Integration Notes

- Firebase Hosting serves the Flutter web build from `flutter/build/web`.
- Flutter bundles `flutter/.env` as a public client asset, so it must contain only client-safe values.
- Supabase Edge Functions verify the user JWT, create durable rows, then publish work to QStash.
- QStash publishes to the Render worker endpoints and forwards `WORKER_SHARED_SECRET`.
- Render runs the FastAPI worker from `worker/` and stores backend secrets in Render environment variables.
- GitHub `main` is the deploy branch for Render auto-deploys.
