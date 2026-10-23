# Page access matrix (None / View / Edit) — design

## Intent
Owners should grant each role access **page by page**, at one of three levels, and the app (web and Flutter) and the
database must behave the same way:

| Level | Meaning |
|---|---|
| **None** | The page does not exist for that user: no menu entry, no tab, no shortcut, no deep link, no data. |
| **View** | The page shows data, but nothing can be created, edited, cancelled, recorded, or **exported**. |
| **Edit** | View + every create / edit / cancel / record / export action on that page. |

Edit always includes View. Owners always have full access. On report-style pages "Edit" means "may export" and is
labelled that way.

Home is called **Home** on web and **Today** in the Flutter app; it is the same page (`HOME`).

## Non-goals
* Per-record permissions (other than the coach "own data" scope below).
* Changing how owners / facility membership work.
* Inventory (switched off in the product).

## How it is built
* **Permission keys stay the enforcement primitive.** `roles` / `role_permissions` / `has_permission()` are unchanged, so
  every existing database check keeps working.
* **`access_pages` (new catalog table)** lists every page: key, label, menu group, which levels it supports, and the
  permission keys that View grants, the additional keys Edit grants, and a few optional "extras" (e.g. *see customer
  phone numbers*). Seeded by migration; read via `list_access_pages()`.
* **New permission keys** are added for pages that had no key of their own (Guest Players, Membership Plans/Schedule/Sessions,
  Coaching Programs/Students/Schedule/Reports, Finance sub-pages, each Report, Roles, Access History, Facility Settings…).
  A backfill grants each new key to every role that already held the related old key, so nobody loses access they had.
  Exports are the one exception: they now need **Edit**.
* **Role editor** becomes a matrix: one row per page, grouped like the app menu, with a None / View / Edit selector, the
  page's extras, and (Coaching) a switch **"Limit to their own coach profile"**. Saving expands the matrix into the role's
  permission keys.
* **Coach scope** is the permission key `COACHING_OWN_ONLY` (a restriction, not a grant). For a non-owner who holds it,
  coaching reads return only their own coach profile, sessions, programs and students, and the Sessions coach filter is
  pre-selected and locked to them.

## Enforcement
* **Web:** sidebar / top search hide pages without View; a route guard shows "no access" for direct URLs; buttons that
  write are hidden or disabled without Edit; every Export is gated by Edit.
* **Flutter:** the bottom bar, the "+" menu, Profile → Manage, Home shortcuts and deep links are all filtered by page access.
  The first visible tab becomes the landing screen when Today is not granted.
* **Database:** restrictive RLS policies on the core tables and a `require_page_access()` guard injected at the top of the
  data RPCs, so the rules hold even if someone calls the API directly. Service-role callers (edge functions) are exempt.

## Open items / calls made
* Legacy `REPORTS_VIEW` / `FINANCE_VIEW` etc. remain and are granted alongside the new keys.
* Page list and default mapping are in migration `0155_page_access_matrix.sql`.
