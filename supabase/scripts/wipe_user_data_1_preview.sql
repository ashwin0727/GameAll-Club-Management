-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1 of 2 — PREVIEW. Deletes NOTHING. Run this first in the Supabase SQL editor.
--
-- Shows who the account is, which facilities it owns, and how many rows in every table would be
-- removed by wipe_user_data_2_delete.sql. Change the email below if needed (same email in step 2).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. The account (this stays — only its business data is wiped).
select u.id as user_id, u.email, p.full_name, p.role
from auth.users u
left join public.profiles p on p.id = u.id
where lower(u.email) = lower('umashankarjun27@gmail.com');

-- 2. The facilities it owns — everything under these is what gets deleted.
select f.id as facility_id, f.name, f.slug, f.created_at
from public.facilities f
join auth.users u on u.id = f.owner_id
where lower(u.email) = lower('umashankarjun27@gmail.com')
order by f.created_at;

-- 3. Rows that would be deleted, per table (tables with nothing to delete are hidden).
--    The table list is built first and MATERIALIZED, so the count is only ever run against tables that
--    really have a facility_id column (otherwise Postgres may try it on every table and fail).
with tabs as materialized (
  select distinct c.table_name::text as table_name
  from information_schema.columns c
  join information_schema.tables tb
    on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
  where c.table_schema = 'public' and c.column_name = 'facility_id'
),
counts as materialized (
  select tabs.table_name,
         (xpath(
            '/row/c/text()',
            query_to_xml(
              format(
                'select count(*) as c from public.%I where facility_id in (select f.id from public.facilities f join auth.users u on u.id = f.owner_id where lower(u.email) = lower(%L))',
                tabs.table_name, 'umashankarjun27@gmail.com'
              ),
              false, true, ''
            )
          ))[1]::text::int as rows_to_delete
  from tabs
)
select table_name, rows_to_delete
from counts
where rows_to_delete > 0
order by rows_to_delete desc, table_name;
