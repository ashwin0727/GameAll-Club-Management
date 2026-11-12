-- A venue can offer any number of its own sports.
--
-- Until now a facility could hold one "Other" sport (facility_sports was unique on (facility_id, sport_id), with a single
-- custom_sport_name). Each custom sport is now its own facility_sports row (sport = Other) told apart by its name, so a venue can add
-- "Table Tennis", "Squash", ... and each gets its own courts. Everything that reads a facility's sports already works per row.

-- unique per venue + sport + custom name (case-insensitive); a catalogue sport still appears once because its custom name is empty
alter table facility_sports drop constraint if exists facility_sports_facility_sport_unique;
drop index if exists facility_sports_facility_sport_name_idx;
create unique index facility_sports_facility_sport_name_idx
  on facility_sports (facility_id, sport_id, coalesce(lower(custom_sport_name), ''));

-- ── sync with any number of custom sports ───────────────────────────────
-- p_sport_ids: the catalogue sports on offer (the Other sport, if listed, is ignored here)
-- p_custom_sport_names: the venue's own sports, by name
-- Anything the venue offered before and is not listed now is switched off (kept, not deleted, so history stays).
create or replace function sync_facility_sports_multi(
  p_facility_id uuid,
  p_sport_ids uuid[],
  p_custom_sport_names text[] default '{}'
) returns setof facility_sports
language plpgsql
as $$
declare
  other_sport_id uuid;
  wanted_ids uuid[];
  wanted_names text[];
  n text;
  clean text;
begin
  select id into other_sport_id from sports where key = 'other';
  wanted_ids := array(select s from unnest(coalesce(p_sport_ids, '{}')) as s where s is distinct from other_sport_id);

  -- names: trimmed, no blanks, no repeats (ignoring case)
  wanted_names := '{}';
  foreach n in array coalesce(p_custom_sport_names, '{}') loop
    clean := btrim(regexp_replace(coalesce(n, ''), '\s+', ' ', 'g'));
    if clean = '' then continue; end if;
    if length(clean) > 50 then raise exception 'A sport name can be up to 50 characters.' using errcode = '23514'; end if;
    if lower(clean) = any (select lower(w) from unnest(wanted_names) as w) then continue; end if;
    wanted_names := wanted_names || clean;
  end loop;

  -- catalogue sports
  insert into facility_sports (facility_id, sport_id, is_active, custom_sport_name)
  select p_facility_id, s, true, null
    from unnest(wanted_ids) as s
  on conflict (facility_id, sport_id, (coalesce(lower(custom_sport_name), ''))) do update
    set is_active = true;

  -- the venue's own sports: reuse a row with the same name, else add one
  if other_sport_id is not null then
    foreach clean in array wanted_names loop
      update facility_sports
         set is_active = true, custom_sport_name = clean
       where facility_id = p_facility_id and sport_id = other_sport_id and lower(custom_sport_name) = lower(clean);
      if not found then
        insert into facility_sports (facility_id, sport_id, is_active, custom_sport_name)
        values (p_facility_id, other_sport_id, true, clean);
      end if;
    end loop;
  end if;

  -- switch off whatever is no longer listed
  update facility_sports fs
     set is_active = false
   where fs.facility_id = p_facility_id
     and fs.is_active
     and not (
       (fs.sport_id = any (wanted_ids) and fs.custom_sport_name is null)
       or (fs.sport_id = other_sport_id and lower(coalesce(fs.custom_sport_name, '')) = any (select lower(w) from unnest(wanted_names) as w))
     );

  return query
    select * from facility_sports where facility_id = p_facility_id and is_active = true;
end;
$$;

grant execute on function sync_facility_sports_multi(uuid, uuid[], text[]) to authenticated;

-- ── the original one-name call keeps working ─────────────────────────────
-- (the older screens still send p_sport_ids with the Other sport inside and a single p_custom_sport_name)
create or replace function sync_facility_sports(
  p_facility_id uuid,
  p_sport_ids uuid[],
  p_custom_sport_name text default null
) returns setof facility_sports
language plpgsql
as $$
declare
  other_sport_id uuid;
begin
  select id into other_sport_id from sports where key = 'other';
  return query
    select * from sync_facility_sports_multi(
      p_facility_id,
      p_sport_ids,
      case when other_sport_id = any (coalesce(p_sport_ids, '{}')) and nullif(btrim(coalesce(p_custom_sport_name, '')), '') is not null
           then array[p_custom_sport_name] else '{}'::text[] end
    );
end;
$$;
