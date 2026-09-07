# Synthetic demo accounts

These scripts create fictional QA accounts only. Every display name begins with `[DEMO]`, every profile uses a non-human geometric avatar, and every row has `is_test = true`. The discovery function excludes these profiles from the real-user feed.

## Setup

1. Run `upgrade_v2.sql` in the Supabase SQL Editor.
2. Copy `.env.example` to `.env`.
3. In Supabase, open **Project settings → API keys** and place the server-only service-role key in `.env`. Never put this key in `index.html`, commit it, or share it.
4. Run with Node 18 or newer:

```powershell
node --env-file=.env scripts/seed-demo.mjs
```

Set `DEMO_ACCOUNT_COUNT` in `.env` to create fewer than 1,000 accounts during a trial run.

## View the accounts

Sign in to `index.html` with an account listed in `admin_users`, then add `?demo=1` to the page URL. For example:

```text
https://your-site.example/index.html?demo=1
```

Demo viewing is enforced by the database: non-admin users cannot reveal test profiles by adding the query parameter. The normal URL continues to show real profiles only.

## Cleanup

```powershell
node --env-file=.env scripts/remove-demo.mjs
```

Cleanup deletes the synthetic Auth users; profile rows and dependent records are removed by database cascades.
