-- Payout step redesign + the admin approval gate.
--
-- 1. Payout accounts: Savings / Current, last-4 for display, no duplicates, at most 5 per facility, and the full account number is
--    no longer readable by the owner's own client (column privileges) — lists show only the last four digits. The platform admin
--    still reads the full number through the admin_* functions (security definer) because they need it to pay out.
-- 2. facility_payout_settings: settlement frequency, minimum payout, which earnings are paid out, auto payout / hold for review.
-- 3. Approval: finishing setup SUBMITS the facility to GameAll. Until the platform admin approves it (status APPROVED) the owner and
--    staff cannot open the dashboard. Facilities that were already complete are grandfathered as APPROVED.
--    Only the platform admin / service role can change the review columns; an owner can only submit (and re-submit after a
--    rejection) through complete_facility_setup / resubmit_facility_for_review.
-- 4. Admin review: queue, one full review payload (Facility Information → Payout), approve / reject, owner notification, audit trail.

-- ── 1. payout methods ───────────────────────────────────────────────────────
alter table facility_payout_methods
  add column if not exists account_type text check (account_type in ('SAVINGS', 'CURRENT')),
  add column if not exists account_last4 text generated always as (case when account_number is null then null else right(account_number, 4) end) stored;

create unique index if not exists facility_payout_methods_unique_upi
  on facility_payout_methods (facility_id, lower(upi_id)) where method_type = 'UPI';
create unique index if not exists facility_payout_methods_unique_bank
  on facility_payout_methods (facility_id, account_number, upper(ifsc)) where method_type = 'BANK';

create or replace function guard_payout_method_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from facility_payout_methods where facility_id = new.facility_id) >= 5 then
    raise exception 'You can add up to 5 payout accounts.' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists payout_method_limit_guard on facility_payout_methods;
create trigger payout_method_limit_guard before insert on facility_payout_methods
  for each row execute function guard_payout_method_limit();

-- The owner's client may no longer read the full account number or who verified it. (Inserts / updates are unaffected; the admin
-- functions are security definer.)
revoke select on facility_payout_methods from anon, authenticated;
grant select (id, facility_id, method_type, account_holder_name, bank_name, ifsc, upi_id, is_primary, verification_status, verified_at,
              verification_note, created_at, updated_at, account_type, account_last4)
  on facility_payout_methods to authenticated;

-- ── 2. payout settings ──────────────────────────────────────────────────────
create table if not exists facility_payout_settings (
  facility_id uuid primary key references facilities (id) on delete cascade,
  settlement_frequency text not null default 'DAILY' check (settlement_frequency in ('DAILY', 'WEEKLY', 'MONTHLY')),
  minimum_payout_inr integer not null default 500 check (minimum_payout_inr between 0 and 1000000),
  include_bookings boolean not null default true,
  include_memberships boolean not null default true,
  include_coaching boolean not null default true,
  auto_payout boolean not null default true,
  hold_for_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table facility_payout_settings enable row level security;
drop policy if exists "payout_settings_owner_all" on facility_payout_settings;
create policy "payout_settings_owner_all" on facility_payout_settings for all
  using (has_facility_role(facility_id, array['owner']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner']::facility_role[]));
drop trigger if exists payout_settings_set_updated_at on facility_payout_settings;
create trigger payout_settings_set_updated_at before update on facility_payout_settings for each row execute function set_updated_at();

-- ── 3. approval state on the facility ───────────────────────────────────────
alter table facilities
  add column if not exists setup_review_status text not null default 'NOT_SUBMITTED'
    check (setup_review_status in ('NOT_SUBMITTED', 'PENDING', 'APPROVED', 'REJECTED')),
  add column if not exists setup_submitted_at timestamptz,
  add column if not exists setup_reviewed_at timestamptz,
  add column if not exists setup_reviewed_by uuid references auth.users (id),
  add column if not exists setup_review_note text;

-- Everything that was already finished before this gate existed keeps working.
update facilities
   set setup_review_status = 'APPROVED', setup_reviewed_at = coalesce(onboarding_completed_at, now())
 where onboarding_step = 'COMPLETED' and setup_review_status = 'NOT_SUBMITTED';

create table if not exists facility_review_events (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  action text not null check (action in ('SUBMITTED', 'RESUBMITTED', 'APPROVED', 'REJECTED', 'REOPENED')),
  actor uuid references auth.users (id),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists facility_review_events_facility_idx on facility_review_events (facility_id, created_at desc);
alter table facility_review_events enable row level security;   -- no policies: only the functions below read or write it

create or replace function guard_facility_setup_review()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or is_platform_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.setup_review_status := 'NOT_SUBMITTED';
    new.setup_submitted_at := null;
    new.setup_reviewed_at := null;
    new.setup_reviewed_by := null;
    new.setup_review_note := null;
    return new;
  end if;

  if new.setup_review_status is distinct from old.setup_review_status
     or new.setup_submitted_at is distinct from old.setup_submitted_at
     or new.setup_reviewed_at is distinct from old.setup_reviewed_at
     or new.setup_reviewed_by is distinct from old.setup_reviewed_by
     or new.setup_review_note is distinct from old.setup_review_note then
    -- The only change an owner may cause: submitting (or re-submitting) for review, from inside our own functions.
    if coalesce(current_setting('gameall.review_submit', true), '') = '1'
       and new.setup_review_status = 'PENDING'
       and old.setup_review_status in ('NOT_SUBMITTED', 'REJECTED')
       and new.setup_reviewed_by is not distinct from old.setup_reviewed_by then
      return new;
    end if;
    raise exception 'The review of your facility is managed by GameAll' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists facilities_setup_review_guard on facilities;
create trigger facilities_setup_review_guard before insert or update on facilities
  for each row execute function guard_facility_setup_review();

-- Finishing setup now also submits the facility for review. Everything else is as in 0195.
create or replace function complete_facility_setup(p_facility_id uuid) returns facilities
language plpgsql
as $$
declare
  result facilities;
  sport_count integer;
  area_count integer;
  schedule_count integer;
  unpriced_sport_count integer;
  payout_count integer;
  image_count integer;
begin
  select * into result from facilities where id = p_facility_id;
  if result.id is null then
    raise exception 'Facility not found' using errcode = 'P0002';
  end if;

  if result.onboarding_step = 'COMPLETED' then
    update profiles set onboarding_completed = true where id = auth.uid() and onboarding_completed = false;
    return result;
  end if;

  if nullif(btrim(coalesce(result.location_url, '')), '') is null then
    raise exception 'The Google Maps location link is required.' using errcode = '23514';
  end if;
  select count(*) into image_count from facility_images where facility_id = p_facility_id;
  if image_count = 0 then
    raise exception 'At least one facility photo is required.' using errcode = '23514';
  end if;

  select count(*) into sport_count from facility_sports where facility_id = p_facility_id and is_active;
  if sport_count = 0 then
    raise exception 'At least one sport is required.' using errcode = '23514';
  end if;

  select count(*) into area_count from courts where facility_id = p_facility_id and not archived;
  if area_count = 0 then
    raise exception 'At least one playing area is required.' using errcode = '23514';
  end if;

  select count(*) into schedule_count from operating_schedules
    where facility_id = p_facility_id and scope_type = 'FACILITY';
  if schedule_count = 0 then
    raise exception 'Operating hours are required.' using errcode = '23514';
  end if;

  select count(*) into unpriced_sport_count
  from facility_sports fs
  where fs.facility_id = p_facility_id
    and fs.is_active
    and not exists (
      select 1 from pricing_rules pr
      join pricing_plans pp on pp.id = pr.pricing_plan_id
      where pp.facility_id = p_facility_id
        and pp.status = 'ACTIVE'
        and pr.facility_sport_id = fs.id
        and pr.playing_area_id is null
        and pr.is_active
    )
    and not (
      exists (select 1 from courts c where c.facility_sport_id = fs.id and not c.archived)
      and not exists (
        select 1 from courts c
        where c.facility_sport_id = fs.id
          and not c.archived
          and not exists (
            select 1 from pricing_rules pr
            join pricing_plans pp on pp.id = pr.pricing_plan_id
            where pp.facility_id = p_facility_id
              and pp.status = 'ACTIVE'
              and pr.playing_area_id = c.id
              and pr.is_active
          )
      )
    );
  if unpriced_sport_count > 0 then
    raise exception 'Pricing is required for every sport.' using errcode = '23514';
  end if;

  select count(*) into payout_count from facility_payout_methods where facility_id = p_facility_id;
  if payout_count = 0 then
    raise exception 'A payout method is required.' using errcode = '23514';
  end if;

  perform set_config('gameall.review_submit', '1', true);
  update facilities
  set onboarding_step = 'COMPLETED', onboarding_completed_at = now(),
      setup_review_status = 'PENDING', setup_submitted_at = now(), setup_review_note = null
  where id = p_facility_id
  returning * into result;
  perform set_config('gameall.review_submit', '', true);

  insert into facility_review_events (facility_id, action, actor) values (p_facility_id, 'SUBMITTED', auth.uid());

  update profiles set onboarding_completed = true where id = auth.uid();

  return result;
end;
$$;

-- After a rejection the owner fixes things and sends the facility back.
create or replace function resubmit_facility_for_review(p_facility_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not has_facility_role(p_facility_id, array['owner']::facility_role[]) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if not exists (select 1 from facilities where id = p_facility_id and setup_review_status = 'REJECTED') then
    raise exception 'This facility is not waiting for changes.' using errcode = '22023';
  end if;
  perform set_config('gameall.review_submit', '1', true);
  update facilities set setup_review_status = 'PENDING', setup_submitted_at = now() where id = p_facility_id;
  perform set_config('gameall.review_submit', '', true);
  insert into facility_review_events (facility_id, action, actor) values (p_facility_id, 'RESUBMITTED', auth.uid());
end;
$$;
revoke all on function resubmit_facility_for_review(uuid) from public;
grant execute on function resubmit_facility_for_review(uuid) to authenticated;

-- The sign-in bundle now carries the verdict so both apps can hold the owner at the "under review" screen.
create or replace function get_session_bundle()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_fac facilities;
begin
  if v_user is null then
    return null;
  end if;

  select f.* into v_fac
  from facilities f
  where f.owner_id = v_user or is_facility_member(f.id)
  order by (f.owner_id = v_user) desc, f.created_at asc
  limit 1;

  return jsonb_build_object(
    'profile', (select to_jsonb(p) from profiles p where p.id = v_user),
    'facility', case when v_fac.id is null then null else to_jsonb(v_fac) end,
    'baseRole', case
      when v_fac.id is null then null
      else coalesce(
        (select fu.role::text from facility_users fu where fu.facility_id = v_fac.id and fu.user_id = v_user),
        case when v_fac.owner_id = v_user then 'owner' else 'staff' end)
    end,
    'permissions', case
      when v_fac.id is null then '[]'::jsonb
      else coalesce((select to_jsonb(array_agg(k)) from my_facility_permissions(v_fac.id) k), '[]'::jsonb)
    end,
    'plan', case when v_fac.id is null then null else my_facility_plan(v_fac.id) end,
    'isPlatformAdmin', is_platform_admin(),
    'approvalStatus', case when v_fac.id is null then null else v_fac.setup_review_status end,
    'approvalNote', case when v_fac.id is null then null else v_fac.setup_review_note end
  );
end;
$$;
grant execute on function get_session_bundle() to authenticated;

-- A light read for the "under review" screen to poll (works for owner and staff of that facility).
create or replace function my_facility_review(p_facility_id uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select case when is_facility_member(f.id) or f.owner_id = auth.uid() then
    jsonb_build_object('status', f.setup_review_status, 'note', f.setup_review_note, 'submittedAt', f.setup_submitted_at, 'reviewedAt', f.setup_reviewed_at)
  end
  from facilities f where f.id = p_facility_id;
$$;
grant execute on function my_facility_review(uuid) to authenticated;

-- ── 4. admin review ─────────────────────────────────────────────────────────
create or replace function admin_list_setup_reviews(p_status text default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', f.id, 'name', f.name, 'city', f.city, 'state', f.state,
      'ownerName', o.full_name, 'ownerEmail', o.email, 'ownerPhone', coalesce(f.business_phone, o.phone),
      'status', f.setup_review_status, 'submittedAt', f.setup_submitted_at, 'reviewedAt', f.setup_reviewed_at,
      'payoutVerified', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'VERIFIED'),
      'payoutTotal', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id)
    ) order by (f.setup_review_status = 'PENDING') desc, coalesce(f.setup_submitted_at, f.created_at) desc)
    from facilities f left join profiles o on o.id = f.owner_id
    where f.setup_review_status <> 'NOT_SUBMITTED'
      and (p_status is null or f.setup_review_status = p_status)
  ), '[]'::jsonb);
end;
$$;
grant execute on function admin_list_setup_reviews(text) to authenticated;

-- Everything the owner entered, Facility Information → Payout, in one payload.
create or replace function admin_get_setup_review(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  f facilities;
  o profiles;
begin
  perform require_platform_admin();
  select * into f from facilities where id = p_facility_id;
  if f.id is null then
    raise exception 'Facility not found.' using errcode = 'P0002';
  end if;
  select * into o from profiles where id = f.owner_id;

  return jsonb_build_object(
    'review', jsonb_build_object('status', f.setup_review_status, 'note', f.setup_review_note, 'submittedAt', f.setup_submitted_at, 'reviewedAt', f.setup_reviewed_at),
    'facility', jsonb_build_object(
      'id', f.id, 'name', f.name, 'type', coalesce(f.custom_facility_type, f.facility_type::text), 'description', f.description,
      'ownership', f.ownership_type, 'businessEmail', f.business_email, 'businessPhone', f.business_phone, 'whatsapp', f.whatsapp_number,
      'contactPerson', f.contact_person_name, 'contactRole', f.contact_person_role, 'contactAltPhone', f.contact_person_alt_phone,
      'address', concat_ws(', ', nullif(f.address_line_1, ''), nullif(f.address_line_2, ''), nullif(f.area, ''), nullif(f.city, ''), nullif(f.state, ''), nullif(f.postal_code, '')),
      'timezone', f.timezone, 'venueType', f.venue_type, 'amenities', f.amenity_keys, 'customAmenities', f.custom_amenities,
      'location', jsonb_build_object('url', f.location_url, 'status', f.location_verification_status),
      'allowOnlineBooking', f.allow_online_booking, 'allowWalkIn', f.allow_walk_in_booking, 'advancePaymentRequired', f.advance_payment_required,
      'allowCancellations', f.allow_cancellations
    ),
    'owner', jsonb_build_object('name', o.full_name, 'email', o.email, 'phone', o.phone),
    'images', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'url', i.url, 'status', i.verification_status) order by i.sort_order, i.created_at)
                         from facility_images i where i.facility_id = f.id), '[]'::jsonb),
    'sports', coalesce((
      select jsonb_agg(jsonb_build_object('name', coalesce(fs.custom_sport_name, s.name), 'active', fs.is_active) order by coalesce(fs.custom_sport_name, s.name))
      from facility_sports fs left join sports s on s.id = fs.sport_id where fs.facility_id = f.id), '[]'::jsonb),
    'courts', coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'sport', coalesce(fs.custom_sport_name, sp.name), 'surface', c.surface,
                                          'hourlyRateInr', c.hourly_rate_inr, 'status', c.status::text) order by c.display_order, c.name)
      from courts c left join facility_sports fs on fs.id = c.facility_sport_id left join sports sp on sp.id = fs.sport_id
      where c.facility_id = f.id and not c.archived), '[]'::jsonb),
    'hours', jsonb_build_object(
      'sportWise', f.sport_wise_hours,
      'days', coalesce((
        select jsonb_agg(jsonb_build_object(
          'day', d.day_of_week, 'closed', d.is_closed, 'is24', d.is_24_hours,
          'slots', coalesce((select jsonb_agg(jsonb_build_object('start', t.start_time, 'end', t.end_time) order by t.display_order)
                              from operating_time_slots t where t.operating_day_id = d.id), '[]'::jsonb)
        ) order by d.day_of_week)
        from operating_days d join operating_schedules sc on sc.id = d.schedule_id
        where sc.facility_id = f.id and sc.scope_type = 'FACILITY'), '[]'::jsonb)
    ),
    'pricing', jsonb_build_object(
      'mode', f.pricing_mode, 'differentWeekend', f.different_weekend_pricing,
      'rules', coalesce((
        select jsonb_agg(jsonb_build_object(
          'sport', coalesce(fs.custom_sport_name, sp.name), 'court', c.name, 'dayType', pr.day_type, 'fullDay', pr.covers_full_day,
          'start', pr.start_time, 'end', pr.end_time, 'amountMinor', pr.amount_minor, 'unit', pr.pricing_unit
        ) order by coalesce(fs.custom_sport_name, sp.name), c.name nulls first, pr.priority, pr.start_time)
        from pricing_rules pr
        join pricing_plans pp on pp.id = pr.pricing_plan_id and pp.status = 'ACTIVE'
        join facility_sports fs on fs.id = pr.facility_sport_id
        left join sports sp on sp.id = fs.sport_id
        left join courts c on c.id = pr.playing_area_id
        where pr.facility_id = f.id and pr.is_active and pr.audience = 'GENERAL'), '[]'::jsonb)
    ),
    'payoutMethods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pm.id, 'type', pm.method_type, 'accountHolderName', pm.account_holder_name, 'bankName', pm.bank_name,
        'accountNumber', pm.account_number, 'accountType', pm.account_type, 'ifsc', pm.ifsc, 'upiId', pm.upi_id,
        'primary', pm.is_primary, 'verification', pm.verification_status, 'note', pm.verification_note
      ) order by pm.is_primary desc, pm.created_at)
      from facility_payout_methods pm where pm.facility_id = f.id), '[]'::jsonb),
    'payoutSettings', (select to_jsonb(ps) - 'facility_id' - 'created_at' from facility_payout_settings ps where ps.facility_id = f.id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('action', e.action, 'note', e.note, 'at', e.created_at) order by e.created_at desc)
                         from facility_review_events e where e.facility_id = f.id), '[]'::jsonb)
  );
end;
$$;
grant execute on function admin_get_setup_review(uuid) to authenticated;

-- Approve or send back. Approval needs at least one verified payout method (the admin verifies them on the same screen).
create or replace function admin_review_facility_setup(p_facility_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  f facilities;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform require_platform_admin();
  if p_decision not in ('APPROVED', 'REJECTED') then
    raise exception 'Choose Approve or Reject.' using errcode = '22023';
  end if;
  select * into f from facilities where id = p_facility_id;
  if f.id is null then
    raise exception 'Facility not found.' using errcode = 'P0002';
  end if;
  if f.setup_review_status = 'NOT_SUBMITTED' then
    raise exception 'The owner has not finished setup yet.' using errcode = '22023';
  end if;
  if p_decision = 'REJECTED' and v_note is null then
    raise exception 'Say what needs to change so the owner can fix it.' using errcode = '22023';
  end if;
  if p_decision = 'APPROVED' and not exists (
       select 1 from facility_payout_methods pm where pm.facility_id = p_facility_id and pm.verification_status = 'VERIFIED') then
    raise exception 'Verify at least one payout method before approving.' using errcode = '22023';
  end if;

  update facilities
     set setup_review_status = p_decision, setup_review_note = case when p_decision = 'REJECTED' then v_note else null end,
         setup_reviewed_at = now(), setup_reviewed_by = auth.uid()
   where id = p_facility_id;

  insert into facility_review_events (facility_id, action, actor, note) values (p_facility_id, p_decision, auth.uid(), v_note);

  insert into notifications (user_id, facility_id, kind, title, body, data)
  values (
    f.owner_id, p_facility_id, 'SETUP_REVIEW',
    case when p_decision = 'APPROVED' then 'Your facility is approved' else 'Changes needed on your facility' end,
    case when p_decision = 'APPROVED' then 'GameAll has approved your setup. You can start managing your facility now.'
         else coalesce(v_note, 'Please review your setup and send it again.') end,
    jsonb_build_object('status', p_decision));
end;
$$;
grant execute on function admin_review_facility_setup(uuid, text, text) to authenticated;

-- Replace the old payout list that exposed the number to anyone able to call it? (unchanged: it is admin-only and security definer.)
-- admin_list_payout_methods (0160) keeps returning the full number to the platform admin; add the account type there too.
create or replace function admin_list_payout_methods(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return jsonb_build_object(
    'facility', (select jsonb_build_object('id', f.id, 'name', f.name, 'city', f.city, 'ownerName', o.full_name, 'ownerEmail', o.email, 'ownerPhone', coalesce(f.business_phone, o.phone))
                 from facilities f left join profiles o on o.id = f.owner_id where f.id = p_facility_id),
    'methods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pm.id, 'type', pm.method_type, 'accountHolderName', pm.account_holder_name, 'bankName', pm.bank_name,
        'accountNumber', pm.account_number, 'accountType', pm.account_type, 'ifsc', pm.ifsc, 'upiId', pm.upi_id, 'primary', pm.is_primary,
        'verification', pm.verification_status, 'verifiedAt', pm.verified_at, 'note', pm.verification_note,
        'createdAt', pm.created_at, 'updatedAt', pm.updated_at
      ) order by pm.is_primary desc, pm.created_at)
      from facility_payout_methods pm where pm.facility_id = p_facility_id), '[]'::jsonb)
  );
end;
$$;
grant execute on function admin_list_payout_methods(uuid) to authenticated;
