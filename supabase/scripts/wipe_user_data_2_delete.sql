-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2 of 2 — DELETE. IRREVERSIBLE. Run only after reading the output of step 1.
--
-- Deletes every facility owned by the account below, and every row under those facilities (bookings,
-- members, memberships, plans, coaching, finance, staff, inventory, maintenance ...).
--
-- KEPT: the sign-in account (auth.users) and its profile — the user can log in and start again at
-- onboarding. NOT touched: other accounts (e.g. staff logins created for the facility), uploaded files in
-- Storage, and anything belonging to a facility this account does not own.
--
-- It runs as ONE statement: if anything goes wrong, nothing is deleted.
--
-- How it copes with foreign keys: it deletes from every table that has a facility_id, retrying in passes
-- so child rows go before the parents that restrict on them, and finally removes the facilities. If a
-- table still can't be cleared it stops with an error and rolls everything back.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_email      constant text := 'umashankarjun27@gmail.com';
  v_user       uuid;
  v_facilities uuid[];
  t            record;
  v_pass       integer;
  v_failed     boolean;
  v_progress   boolean;
  v_rows       bigint;
  v_total      bigint := 0;
begin
  select u.id into v_user from auth.users u where lower(u.email) = lower(v_email);
  if v_user is null then
    raise exception 'No account with the email %', v_email;
  end if;

  select coalesce(array_agg(f.id), '{}') into v_facilities from public.facilities f where f.owner_id = v_user;
  if cardinality(v_facilities) = 0 then
    raise notice 'Nothing to delete: % owns no facilities.', v_email;
    return;
  end if;

  for v_pass in 1..25 loop
    v_failed := false;
    v_progress := false;

    for t in
      select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
      where c.table_schema = 'public' and c.column_name = 'facility_id'
      order by c.table_name
    loop
      begin
        execute format('delete from public.%I where facility_id = any($1)', t.table_name) using v_facilities;
        get diagnostics v_rows = row_count;
        if v_rows > 0 then
          v_progress := true;
          v_total := v_total + v_rows;
        end if;
      exception when foreign_key_violation then
        -- Another table still points at these rows; they'll go on a later pass.
        v_failed := true;
      end;
    end loop;

    exit when not v_failed;
    if not v_progress then
      raise exception 'Stuck after pass %: some tables still have rows other tables depend on. Nothing was deleted.', v_pass;
    end if;
  end loop;

  delete from public.facilities where id = any(v_facilities);

  if exists (select 1 from public.facilities f where f.id = any(v_facilities)) then
    raise exception 'A facility could not be removed. Nothing was deleted.';
  end if;

  raise notice 'Done: % rows deleted from facility tables, % facilities removed. Account % kept.', v_total, cardinality(v_facilities), v_email;
end
$$;

-- Check afterwards: both should return no rows.
-- select id, name from public.facilities f join auth.users u on u.id = f.owner_id where lower(u.email) = lower('umashankarjun27@gmail.com');
