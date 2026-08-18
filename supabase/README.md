# Database

`migrations/0001_init.sql` is the whole schema. It was **rewritten** around
facilities as the tenant root, so it is not an incremental patch on top of the
version that may already be applied to your project.

## Model

```
auth.users → profiles → facility_users → facilities
                                           ├── facility_sports → sports
                                           │        └── courts
                                           ├── membership_plans → memberships → payments
                                           ├── bookings (court × time)
                                           └── inventory_items → inventory_transactions
```

Every operational table carries `facility_id`, so RLS resolves "may this user
see this row?" with one membership lookup instead of a multi-level join.

Changes from the previous version, for anyone reading a diff:

- `stations` is gone; `courts` replaces it, tied to a sport the facility has
  enabled (composite FK into `facility_sports`).
- `profiles` gained `email` and `onboarding_completed`; `handle_new_user` now
  copies both from the signup metadata, and a second trigger keeps `email` in
  step when a user changes it through Supabase Auth.
- Overlapping bookings on one court are rejected by the database
  (`bookings_no_overlap`, a GiST exclusion constraint over `pending` and
  `confirmed` rows) rather than by application code.
- Facility-scoped RLS via the `is_facility_member` / `has_facility_role`
  SECURITY DEFINER helpers.

## Applying it

**On a project that has never run `0001`** — paste the file into the Supabase
SQL editor, or `supabase db push` if the project is linked.

**On a project where the old `0001` is already applied**, the objects it creates
already exist and the script will fail partway. The schema has to be reset
first, which **destroys all data in `public`** (auth users survive — they live in
`auth`, though their `profiles` rows do not):

```sql
drop schema public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
```

Then run `0001_init.sql`. With the CLI, `supabase db reset --linked` does the
equivalent. Take a backup first if there is anything in there worth keeping.

## Auth settings to match

In **Authentication → Providers → Email**: keep *Confirm email* **on** — the
signup flow routes through `/verify-email` and expects a confirmation link.

In **Authentication → URL Configuration**: set the Site URL and add
`http://localhost:3000/auth/callback` (plus the deployed equivalent) to the
redirect allow-list. Confirmation and recovery links both land on
`/auth/callback`, which exchanges the code for a session.

## Types

`src/types/database.types.ts` is hand-written to match this file. After changing
the schema, regenerate and diff:

```bash
supabase gen types typescript --linked > src/types/database.types.ts
```