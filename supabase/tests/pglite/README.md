# Database scenario tests (no Docker)

Applies **every** migration, in order, to an in-memory Postgres ([PGlite](https://pglite.dev)) with small stand-ins for Supabase's own
`auth` and `storage` objects, then runs scenario checks against the newer database code: plans and entitlements, the platform admin,
notifications, account deletion, page-access permissions and the merged "fewer requests" functions.

```
cd supabase/tests/pglite
npm install
npm test
```

It prints `passed: N, failed: 0` (and the name of anything that fails). It takes about a minute.

What it does and does not cover: PGlite runs as one superuser, so **Row Level Security is not exercised** here. The checks cover the
functions themselves (most are `SECURITY DEFINER` and check permissions on their own) and every migration applying cleanly. The older
Docker-based tests in `../integration` cover row-level security.
