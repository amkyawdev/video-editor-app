# Integrations: Supabase, Cloudflare Worker, AI providers, Firebase

These integrations are **scaffolded, not connected**. No keys are committed.
The app still runs fully offline without them.

## 1. Supabase (profiles, project metadata, preferences, jobs)

- Project URL: `https://cmskoskdupwabkkzelam.supabase.co` (configured by you).
- Migration: `supabase/migrations/0001_init.sql` creates `profiles`, `projects`,
  `preferences`, `jobs`, enables **RLS**, and adds owner-only policies
  (`auth.uid() = owner_id` / `id`). Media files are never stored in Postgres.
- Apply with the Supabase SQL editor or `supabase db push`.
- Client configuration (build-time only):

```bash
flutter build apk --debug \
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=https://cmskoskdupwabkkzelam.supabase.co \
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY=<publishable-key>
```

- Use **only** the publishable/anon key on the client. Never embed a
  `service_role` key in the app, CI logs, or this repository.
- Two publishable keys were supplied in chat. This repository does **not**
  decide which is valid. Verify in Supabase → Project Settings → API that the
  key's project ref matches `cmskoskdupwabkkzelam`, then put that key in a local
  `.env`/CI secret. Do not paste keys into source.
- `lib/core/config/app_config.dart` reads the values; `AppConfig.hasSupabase`
  tells the UI whether the integration is configured.

## 2. Cloudflare Worker translation proxy

- Source: `cloudflare/worker/src/index.ts`; config: `wrangler.toml`.
- Features: POST-only, JSON validation, CORS allow-list, per-IP rate limit
  (30 req/min per isolate), 12k character cap, 45 s upstream timeout, structured
  errors (`invalid_texts`, `rate_limited`, `provider_error`, `provider_timeout`,
  `bad_provider_output`).
- Provider credentials are Worker secrets, never client-side:

```bash
cd cloudflare/worker
npx wrangler secret put TRANSLATION_PROVIDER_URL
npx wrangler secret put TRANSLATION_PROVIDER_KEY
npx wrangler deploy
```

- GitHub Actions secrets (placeholders, not set by this repo):
  `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_WORKER_NAME`.
- Client: `lib/data/services/ai/cloudflare_translation_service.dart` with
  timeout + retry + honest error mapping, configured by
  `--dart-define=CLOUDFLARE_WORKER_URL=https://<worker>.workers.dev`.
- **No deployment has been performed or verified.**

### Security notice

A Cloudflare API token and Supabase keys were pasted into chat. Treat the
Cloudflare token as **exposed**: revoke it now in Cloudflare, then create a
least-privilege token scoped only to the account/Worker you deploy. Store the
rotated token only as a GitHub Actions secret or local environment value. This
repository never writes it to files, workflow YAML, logs, or commits.

## 3. AI provider plugins (Gemini / OpenAI-compatible)

The Worker is provider-agnostic (OpenAI-compatible chat completions). For a
direct on-device provider, add an adapter behind the existing
`LlamaRunner`/translation interfaces and store user keys in Android secure
storage (`EncryptedSharedPreferences` / Keystore). Not implemented yet; do not
show a key field that silently does nothing.

## 4. Firebase Auth

Still blocked by the Android package mismatch described in `PROJECT_DOCS.md`
(Firebase app package `com.aungmyokyaw.sever` vs this app's
`dev.amkyaw.video_editor_app`). `android-building.yml` can decode a
`GOOGLE_SERVICES_JSON_BASE64` secret at build time, but no Firebase plugin or
auth UI is enabled until a matching app config exists.
