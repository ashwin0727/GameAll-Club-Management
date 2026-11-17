-- 0204: remove the long dash ("—") from text the database itself generates, so it never reaches the apps or a screenshot.
--
-- The apps and the web site were already cleaned. What remains lives inside SQL functions: ledger descriptions
-- ("Membership payment — Gold"), booking notes ("Purpose — Notes"), report placeholders and error messages.
--
-- Rather than copy ~40 functions into this file (and risk reverting a later edit), the block below finds every function in the
-- public schema whose body contains a long dash, rewrites it with the same rules, and re-creates it in place.
-- CREATE OR REPLACE keeps the owner, the grants, SECURITY DEFINER and the search_path setting.
--
-- The rules (in this order):
--   " — "  becomes  ": "    ("Guest Booking — Asha" -> "Guest Booking: Asha", "Unsupported window — expected 30" -> "Unsupported window: expected 30")
--   " —"   becomes  ":"     ("Membership payment —" -> "Membership payment:")
--   "—"    becomes  "-"     (an empty placeholder; the apps already treat "-" as empty)
--
-- Safe to run more than once: after the first run no function contains the character, so nothing is selected.

do $fix$
declare
  r        record;
  v_def    text;
  v_new    text;
  v_dash   constant text := chr(8212);   -- the long dash
  v_fixed  integer := 0;
  v_failed integer := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       and p.prosrc like '%' || v_dash || '%'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')   -- not part of an extension
  loop
    begin
      v_def := pg_get_functiondef(r.oid);
      v_new := replace(replace(replace(v_def, ' ' || v_dash || ' ', ': '), ' ' || v_dash, ':'), v_dash, '-');
      if v_new <> v_def then
        execute v_new;
        v_fixed := v_fixed + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
      raise notice 'Could not rewrite function % (%): %', r.proname, r.oid, sqlerrm;
    end;
  end loop;
  raise notice 'Long dashes removed from % function(s); % could not be rewritten.', v_fixed, v_failed;
end
$fix$;

-- The permission catalogue (shown on the Staff and Roles screens) is data, not a function.
do $fix$
declare
  v_dash constant text := chr(8212);
  c      record;
begin
  for c in
    select table_name, column_name
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('permissions', 'plans', 'plan_pages')
       and data_type in ('text', 'character varying')
  loop
    execute format(
      'update public.%I set %I = replace(replace(replace(%I, %L, %L), %L, %L), %L, %L) where %I like %L',
      c.table_name, c.column_name, c.column_name,
      ' ' || v_dash || ' ', ': ', ' ' || v_dash, ':', v_dash, '-',
      c.column_name, '%' || v_dash || '%');
  end loop;
end
$fix$;
