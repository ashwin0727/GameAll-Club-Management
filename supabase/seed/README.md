# Test venues (temporary, for trying the Player app)

Fake data so the Venues, Memberships, Coaching and venue pages have something real to show. **For testing only: remove it afterwards.**

| File | What it does |
|---|---|
| `test_venues_seed.sql` | Loads 6 venues in Chennai, Bengaluru and Hyderabad, with courts, rates, opening hours, photos, map links, memberships and coaching, plus 3 test players. |
| `test_venues_cleanup.sql` | Removes all of it, and only it. Safe to run twice. |

## Use

1. Make sure migrations `0169` to `0174` are applied.
2. Supabase dashboard → **SQL Editor** → paste `test_venues_seed.sql` → **Run**. The last query lists what was loaded.
3. Open the Player app, pick **Chennai** (3 venues), **Bengaluru** (2) or **Hyderabad** (1).
4. Log in with a test number to see player data (while codes are off, the number alone signs you in):
   - `9000000001` Arun Test: a membership at Champz Turf, coaching at Smash Arena, 2 upcoming bookings
   - `9000000002` Meena Test: a membership at Ace Pickle Club
   - `9000000003` Ravi Test: one booking
5. When you are done: paste `test_venues_cleanup.sql` → **Run**. The last query shows zeros when everything is gone.

## What each venue is for

| Venue | City | Try this |
|---|---|---|
| Champz Turf | Chennai | Everything on: 3 approved photos, verified map, all five amenities, plans, coaching |
| Smash Arena | Chennai | Badminton + tennis, plans, coaching, no equipment rental |
| Kickoff Sports | Chennai | Photos and map **waiting for review** (shows the drawn court, no "Verified" badge, no Maps button), no plans |
| Ace Pickle Club | Bengaluru | Pickleball + padel (a custom sport), plans but no coaching |
| Hoops & Rackets | Bengaluru | Basketball (custom sport) + badminton + tennis, no parking |
| Boundary Cricket Hub | Hyderabad | Cricket nets + football, no plans or coaching: the venue page hides those sections |

## Notes

- Everything is tagged: facility slugs start with `seed-`, the owner is `seed.owner@gameall.test`, test phones are `9000000001` to `9000000003`. The cleanup finds them by those markers.
- Photos are public-domain / Creative Commons images from Wikimedia Commons, hot-linked. Fine for testing, not for production.
- The owner account has no password, so nobody can sign in as it.
- The scenario tests (`supabase/tests/pglite`) load the seed, check the Player functions against it, run the cleanup and check the database is back exactly as it was.
