-- ═══════════════════════════════════════════════════════════════════════════
-- Coach onboarding — a 5-step, resumable-draft flow for adding a coach.
--
--   1 Identity & Basic Profile        → start_coach_onboarding (creates the coach, INACTIVE, + a DRAFT profile)
--   2 Expertise & Credentials         → save_coach_onboarding_step(…, 2, …)
--   3 Sessions & Pricing→ save_coach_onboarding_step(…, 3, …)
--   4 Payments, Payouts & KYC         → save_coach_onboarding_step(…, 4, …)   (needs COACHING_MANAGE_COACH_PAYOUTS)
--   5 Review & Agreements             → complete_coach_onboarding (coach becomes ACTIVE)
--
-- A draft coach is coaches.status = 'INACTIVE', so every "active coaches" picker (session wizard, etc.) never offers one.
-- Bank / tax details live in coach_payout_details, which has RLS enabled and NO policies: only the SECURITY DEFINER RPCs
-- below can touch it, and get_coach_onboarding only ever returns them masked (last 4 characters).
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Permission. 0072's one-time owner seed does not reach later rows, so the owner role is granted it here.
-- (Managers deliberately do not get bank/tax access by default; an owner can add it to any custom role.)
-- ─────────────────────────────────────────────────────────────────────────
insert into permissions (key, module, action, label, description, is_dangerous, sort_order) values
  ('COACHING_MANAGE_COACH_PAYOUTS', 'Coaching', 'MANAGE_COACH_PAYOUTS', 'Manage coach payout & KYC details',
   'Enter and view (masked) a coach''s bank, UPI and tax details.', true, 1115)
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_key)
values ('00000000-0000-0000-0000-0000000000a1'::uuid, 'COACHING_MANAGE_COACH_PAYOUTS')
on conflict do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists coach_profiles (
  coach_id uuid primary key references coaches(id) on delete cascade,
  facility_id uuid not null references facilities(id) on delete cascade,
  onboarding_status text not null default 'DRAFT' check (onboarding_status in ('DRAFT', 'COMPLETE')),
  current_step integer not null default 2 check (current_step between 1 and 5),
  steps_done integer[] not null default '{}',
  payout_status text not null default 'PENDING' check (payout_status in ('PENDING', 'COMPLETE')),
  -- step 1
  display_name text,
  location text,
  timezone text not null default 'Asia/Kolkata',
  languages text[] not null default '{}',
  -- step 2
  niche text,
  sub_specialties text[] not null default '{}',
  target_audience text[] not null default '{}',
  methodology text,
  certificates jsonb not null default '[]'::jsonb,
  -- step 3
  session_formats text[] not null default '{}',
  session_durations integer[] not null default '{}',
  -- Coaching amounts in paise (whole rupees x 100). Display now, transaction inputs later.
  per_session_rate_minor integer check (per_session_rate_minor is null or per_session_rate_minor > 0),
  weekly_rate_minor integer check (weekly_rate_minor is null or weekly_rate_minor > 0),
  monthly_rate_minor integer check (monthly_rate_minor is null or monthly_rate_minor > 0),
  -- step 5
  legal_accepted_at timestamptz,
  legal_accepted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Upgrade a table created by an earlier copy of this migration: add the three amounts (carrying the old
-- single-session rate over as the per-session amount), then drop the retired columns. Safe to re-run.
alter table coach_profiles add column if not exists per_session_rate_minor integer check (per_session_rate_minor is null or per_session_rate_minor > 0);
alter table coach_profiles add column if not exists weekly_rate_minor integer check (weekly_rate_minor is null or weekly_rate_minor > 0);
alter table coach_profiles add column if not exists monthly_rate_minor integer check (monthly_rate_minor is null or monthly_rate_minor > 0);
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'coach_profiles' and column_name = 'single_session_rate_minor') then
    update coach_profiles set per_session_rate_minor = single_session_rate_minor
    where per_session_rate_minor is null and single_session_rate_minor is not null;
  end if;
end $$;
alter table coach_profiles drop column if exists single_session_rate_minor;
alter table coach_profiles drop column if exists packages;
alter table coach_profiles drop column if exists max_active_clients;

create index if not exists coach_profiles_facility_idx on coach_profiles (facility_id, onboarding_status);

create table if not exists coach_payout_details (
  coach_id uuid primary key references coaches(id) on delete cascade,
  facility_id uuid not null references facilities(id) on delete cascade,
  entity_type text not null check (entity_type in ('INDIVIDUAL', 'BUSINESS')),
  legal_name text,
  business_address text,
  tax_id text,
  payout_method text not null check (payout_method in ('BANK_TRANSFER', 'UPI')),
  account_holder_name text,
  account_number text,
  ifsc text,
  upi_id text,
  currency text not null default 'INR' check (currency = 'INR'),
  payout_frequency text not null check (payout_frequency in ('WEEKLY', 'BIWEEKLY', 'MONTHLY')),
  cancellation_policy text,
  updated_at timestamptz not null default now()
);

-- RLS on, no policies: nothing reads or writes these tables except the SECURITY DEFINER RPCs below.
alter table coach_profiles enable row level security;
alter table coach_payout_details enable row level security;


-- ─────────────────────────────────────────────────────────────────────────
-- Private bucket for certificate uploads. Path: '<facility_id>/<coach_id>/<file>'.
-- ─────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('coach-credentials', 'coach-credentials', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

drop policy if exists "coach_credentials_storage_select" on storage.objects;
drop policy if exists "coach_credentials_storage_insert" on storage.objects;
drop policy if exists "coach_credentials_storage_delete" on storage.objects;

create policy "coach_credentials_storage_select" on storage.objects for select
  using (bucket_id = 'coach-credentials'
         and has_permission(((storage.foldername(name))[1])::uuid, 'COACHING_MANAGE_COACHES'));
create policy "coach_credentials_storage_insert" on storage.objects for insert
  with check (bucket_id = 'coach-credentials'
              and has_permission(((storage.foldername(name))[1])::uuid, 'COACHING_MANAGE_COACHES'));
create policy "coach_credentials_storage_delete" on storage.objects for delete
  using (bucket_id = 'coach-credentials'
         and has_permission(((storage.foldername(name))[1])::uuid, 'COACHING_MANAGE_COACHES'));


-- ─────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _coach_json_text_array(j jsonb) returns text[]
language sql immutable as $$
  select case when j is null or jsonb_typeof(j) <> 'array' then '{}'::text[]
              else coalesce(array(select nullif(trim(e), '') from jsonb_array_elements_text(j) e where nullif(trim(e), '') is not null), '{}'::text[]) end
$$;

create or replace function _coach_json_int_array(j jsonb) returns integer[]
language sql immutable as $$
  select case when j is null or jsonb_typeof(j) <> 'array' then '{}'::integer[]
              else coalesce(array(select e::integer from jsonb_array_elements_text(j) e), '{}'::integer[]) end
$$;

create or replace function _coach_mask(v text) returns text
language sql immutable as $$
  select case when v is null or v = '' then null
              else repeat('X', greatest(length(v) - 4, 0)) || right(v, 4) end
$$;

-- Upper-cases and strips every space / dash — so a pasted "sbin 0001234" is accepted exactly as the clients accept it.
create or replace function _coach_norm_code(v text) returns text
language sql immutable as $$
  select upper(regexp_replace(coalesce(v, ''), '[\s-]', '', 'g'))
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- Step 1: create the coach (INACTIVE) + its DRAFT profile. Idempotent for a draft (a double tap returns the same id).
-- p_data: displayName, location, timezone, languages[], shortBio, dateOfBirth
-- ─────────────────────────────────────────────────────────────────────────
create or replace function start_coach_onboarding(p_facility_id uuid, p_user_id uuid, p_data jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coach coaches;
  v_existing uuid;
  v_dob date := nullif(p_data->>'dateOfBirth', '')::date;
  v_display text := nullif(trim(coalesce(p_data->>'displayName', '')), '');
  v_tz text := coalesce(nullif(trim(coalesce(p_data->>'timezone', '')), ''), 'Asia/Kolkata');
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  if v_display is null then
    raise exception 'Enter the coach''s display name.' using errcode = '22023';
  end if;
  if not exists (select 1 from pg_timezone_names where name = v_tz) then
    raise exception 'Choose a valid timezone.' using errcode = '22023';
  end if;

  select id into v_existing from coaches where facility_id = p_facility_id and user_id = p_user_id;
  if v_existing is not null then
    if exists (select 1 from coach_profiles where coach_id = v_existing and onboarding_status = 'DRAFT') then
      -- Resume: refresh the identity fields instead of failing.
      update coach_profiles set
        display_name = v_display,
        location = nullif(trim(coalesce(p_data->>'location', '')), ''),
        timezone = v_tz,
        languages = _coach_json_text_array(p_data->'languages'),
        updated_at = now()
      where coach_id = v_existing;
      return v_existing;
    end if;
    raise exception 'This staff member already has a coaching profile.' using errcode = '23505';
  end if;

  select * into v_coach from add_coach(
    p_facility_id, p_user_id, null, null, null,
    nullif(trim(coalesce(p_data->>'shortBio', '')), ''),
    null, 'INACTIVE', null, null, null, null, v_dob
  );

  insert into coach_profiles (coach_id, facility_id, current_step, steps_done, display_name, location, timezone, languages)
  values (
    v_coach.id, p_facility_id, 2, array[1], v_display,
    nullif(trim(coalesce(p_data->>'location', '')), ''), v_tz,
    _coach_json_text_array(p_data->'languages')
  );
  return v_coach.id;
end;
$$;
grant execute on function start_coach_onboarding(uuid, uuid, jsonb) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Steps 1-4 (re)save. p_data keys per step:
--   1 displayName, location, timezone, languages[], shortBio, dateOfBirth
--   2 niche, subSpecialties[], experienceYears, targetAudience[], methodology,
--     certificates[{name,issuer,year,path}], sportIds[], expertiseLevels[]
--   3 sessionFormats[], sessionDurations[], defaultSessionDurationMinutes, perSessionRateMinor, weeklyRateMinor,
--     monthlyRateMinor (optional; whole-rupee amounts in paise, > 0 when given). Availability is no longer asked here.
--   4 entityType, legalName, businessAddress, taxId, payoutMethod, accountHolderName, accountNumber, ifsc, upiId,
--     payoutFrequency, cancellationPolicy
-- ─────────────────────────────────────────────────────────────────────────
create or replace function save_coach_onboarding_step(p_coach_id uuid, p_step integer, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c coaches;
  p coach_profiles;
  x jsonb;
  v_tz text;
  v_certs jsonb;
  v_formats text[];
  v_durations integer[];
  v_rate integer;
  v_weekly integer;
  v_monthly integer;
  v_exp numeric;
  v_default integer;
  v_old coach_payout_details;
  v_entity text;
  v_method text;
  v_tax text;
  v_acct text;
  v_ifsc text;
  v_upi text;
  v_freq text;
begin
  select * into c from coaches where id = p_coach_id;
  if c.id is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(c.facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  select * into p from coach_profiles where coach_id = p_coach_id for update;
  if p.coach_id is null then
    raise exception 'This coach has no onboarding record.' using errcode = 'P0002';
  end if;
  if p_step not between 1 and 4 then
    raise exception 'Unknown onboarding step.' using errcode = '22023';
  end if;

  if p_step = 1 then
    v_tz := coalesce(nullif(trim(coalesce(p_data->>'timezone', '')), ''), p.timezone);
    if not exists (select 1 from pg_timezone_names where name = v_tz) then
      raise exception 'Choose a valid timezone.' using errcode = '22023';
    end if;
    if nullif(trim(coalesce(p_data->>'displayName', '')), '') is null then
      raise exception 'Enter the coach''s display name.' using errcode = '22023';
    end if;
    update coach_profiles set
      display_name = trim(p_data->>'displayName'),
      location = nullif(trim(coalesce(p_data->>'location', '')), ''),
      timezone = v_tz,
      languages = _coach_json_text_array(p_data->'languages'),
      updated_at = now()
    where coach_id = p_coach_id;
    perform update_coach(p_coach_id, null, null, null, nullif(trim(coalesce(p_data->>'shortBio', '')), ''),
                         null, null, null, null, null, null, nullif(p_data->>'dateOfBirth', '')::date, null);

  elsif p_step = 2 then
    v_exp := nullif(p_data->>'experienceYears', '')::numeric;
    if nullif(trim(coalesce(p_data->>'niche', '')), '') is null then
      raise exception 'Choose the coaching niche.' using errcode = '22023';
    end if;
    if v_exp is not null and v_exp < 0 then
      raise exception 'Years of experience cannot be negative.' using errcode = '22023';
    end if;
    v_certs := coalesce(p_data->'certificates', '[]'::jsonb);
    if jsonb_typeof(v_certs) <> 'array' then
      raise exception 'Certificates must be a list.' using errcode = '22023';
    end if;
    for x in select * from jsonb_array_elements(v_certs) loop
      if nullif(trim(coalesce(x->>'name', '')), '') is null then
        raise exception 'Every certificate needs a name.' using errcode = '22023';
      end if;
      -- An uploaded file must live under this coach's own folder in the credentials bucket.
      if nullif(x->>'path', '') is not null
         and (x->>'path') not like (c.facility_id::text || '/' || c.id::text || '/%') then
        raise exception 'A certificate file does not belong to this coach.' using errcode = '22023';
      end if;
    end loop;
    update coach_profiles set
      niche = trim(p_data->>'niche'),
      sub_specialties = _coach_json_text_array(p_data->'subSpecialties'),
      target_audience = _coach_json_text_array(p_data->'targetAudience'),
      methodology = nullif(trim(coalesce(p_data->>'methodology', '')), ''),
      certificates = v_certs,
      updated_at = now()
    where coach_id = p_coach_id;
    -- Mirror the fields the rest of the coaching module already reads off `coaches`.
    perform update_coach(
      p_coach_id,
      trim(p_data->>'niche'),
      v_exp,
      nullif((select string_agg(e->>'name', ', ') from jsonb_array_elements(v_certs) e), ''),
      null, null, null, null,
      case when p_data ? 'sportIds' then array(select jsonb_array_elements_text(p_data->'sportIds')::uuid) end,
      case when p_data ? 'expertiseLevels' then _coach_json_text_array(p_data->'expertiseLevels') end,
      null, null, null
    );

  elsif p_step = 3 then
    v_formats := _coach_json_text_array(p_data->'sessionFormats');
    v_durations := _coach_json_int_array(p_data->'sessionDurations');
    v_rate := nullif(p_data->>'perSessionRateMinor', '')::integer;
    v_weekly := nullif(p_data->>'weeklyRateMinor', '')::integer;
    v_monthly := nullif(p_data->>'monthlyRateMinor', '')::integer;
    v_default := nullif(p_data->>'defaultSessionDurationMinutes', '')::integer;
    if array_length(v_formats, 1) is null or exists (select 1 from unnest(v_formats) f where f not in ('ONE_TO_ONE', 'GROUP', 'ASYNC')) then
      raise exception 'Choose at least one session format.' using errcode = '22023';
    end if;
    if array_length(v_durations, 1) is null or exists (select 1 from unnest(v_durations) d where d <= 0) then
      raise exception 'Choose at least one session duration.' using errcode = '22023';
    end if;
    -- The three coaching amounts are optional; any that is given must be greater than zero.
    if v_rate is not null and v_rate <= 0 then
      raise exception 'The per-session coaching amount must be greater than zero.' using errcode = '22023';
    end if;
    if v_weekly is not null and v_weekly <= 0 then
      raise exception 'The weekly coaching amount must be greater than zero.' using errcode = '22023';
    end if;
    if v_monthly is not null and v_monthly <= 0 then
      raise exception 'The monthly coaching amount must be greater than zero.' using errcode = '22023';
    end if;
    if p_data ? 'availability' then
      for x in select * from jsonb_array_elements(coalesce(p_data->'availability', '[]'::jsonb)) loop
        if (x->>'endTime')::time <= (x->>'startTime')::time then
          raise exception 'Each availability slot must end after it starts.' using errcode = '22023';
        end if;
      end loop;
    end if;
    -- The same day twice, or two slots that overlap on a day, are rejected (touching slots are fine).
    if p_data ? 'availability' and exists (
      select 1
      from jsonb_array_elements(coalesce(p_data->'availability', '[]'::jsonb)) with ordinality as a(w, i)
      join jsonb_array_elements(coalesce(p_data->'availability', '[]'::jsonb)) with ordinality as b(w, j) on a.i < b.j
      where (a.w->>'dayOfWeek') = (b.w->>'dayOfWeek')
        and (a.w->>'startTime')::time < (b.w->>'endTime')::time
        and (b.w->>'startTime')::time < (a.w->>'endTime')::time
    ) then
      raise exception 'Two availability slots on the same day overlap or repeat. Remove or change one of them.' using errcode = '22023';
    end if;
    update coach_profiles set
      session_formats = v_formats,
      session_durations = v_durations,
      per_session_rate_minor = v_rate,
      weekly_rate_minor = v_weekly,
      monthly_rate_minor = v_monthly,
      updated_at = now()
    where coach_id = p_coach_id;
    perform update_coach(p_coach_id, null, null, null, null, v_rate, null, null, null, null,
                         coalesce(v_default, v_durations[1]), null, null);
    if p_data ? 'availability' then
      perform set_coach_availability(p_coach_id, p_data->'availability');
    end if;

  else
    if not has_permission(c.facility_id, 'COACHING_MANAGE_COACH_PAYOUTS') then
      raise exception 'You don''t have permission to manage coach payout details.' using errcode = '42501';
    end if;
    select * into v_old from coach_payout_details where coach_id = p_coach_id;
    v_entity := p_data->>'entityType';
    v_method := p_data->>'payoutMethod';
    v_freq := p_data->>'payoutFrequency';
    v_tax := _coach_norm_code(coalesce(nullif(p_data->>'taxId', ''), v_old.tax_id));
    -- A blank account number / IFSC / UPI id means "keep what is saved" (the screen only ever shows them masked).
    v_acct := regexp_replace(coalesce(nullif(p_data->>'accountNumber', ''), v_old.account_number, ''), '\s', '', 'g');
    v_ifsc := _coach_norm_code(coalesce(nullif(p_data->>'ifsc', ''), v_old.ifsc));
    v_upi := nullif(trim(coalesce(nullif(p_data->>'upiId', ''), v_old.upi_id, '')), '');

    if v_entity not in ('INDIVIDUAL', 'BUSINESS') then
      raise exception 'Choose Individual or Business.' using errcode = '22023';
    end if;
    if v_entity = 'BUSINESS' and (nullif(trim(coalesce(p_data->>'legalName', v_old.legal_name, '')), '') is null
                                  or nullif(trim(coalesce(p_data->>'businessAddress', v_old.business_address, '')), '') is null) then
      raise exception 'A business needs its legal name and address.' using errcode = '22023';
    end if;
    if v_tax !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' and v_tax !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then
      raise exception 'Enter a valid PAN or GSTIN.' using errcode = '22023';
    end if;
    if v_method not in ('BANK_TRANSFER', 'UPI') then
      raise exception 'Choose a payout method.' using errcode = '22023';
    end if;
    if v_freq not in ('WEEKLY', 'BIWEEKLY', 'MONTHLY') then
      raise exception 'Choose a payout frequency.' using errcode = '22023';
    end if;
    if v_method = 'BANK_TRANSFER' then
      if nullif(trim(coalesce(p_data->>'accountHolderName', v_old.account_holder_name, '')), '') is null then
        raise exception 'Enter the account holder name.' using errcode = '22023';
      end if;
      if v_acct !~ '^[0-9]{9,18}$' then
        raise exception 'Enter a valid account number (9 to 18 digits).' using errcode = '22023';
      end if;
      if v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then
        raise exception 'Enter a valid IFSC code.' using errcode = '22023';
      end if;
    else
      if v_upi is null or v_upi !~ '^[A-Za-z0-9.\-_]{2,256}@[A-Za-z]{2,64}$' then
        raise exception 'Enter a valid UPI ID.' using errcode = '22023';
      end if;
    end if;

    insert into coach_payout_details (
      coach_id, facility_id, entity_type, legal_name, business_address, tax_id, payout_method,
      account_holder_name, account_number, ifsc, upi_id, payout_frequency, cancellation_policy
    ) values (
      p_coach_id, c.facility_id, v_entity,
      nullif(trim(coalesce(p_data->>'legalName', '')), ''),
      nullif(trim(coalesce(p_data->>'businessAddress', '')), ''),
      v_tax, v_method,
      nullif(trim(coalesce(p_data->>'accountHolderName', '')), ''),
      case when v_method = 'BANK_TRANSFER' then v_acct end,
      case when v_method = 'BANK_TRANSFER' then v_ifsc end,
      case when v_method = 'UPI' then v_upi end,
      v_freq,
      nullif(trim(coalesce(p_data->>'cancellationPolicy', '')), '')
    )
    on conflict (coach_id) do update set
      entity_type = excluded.entity_type, legal_name = excluded.legal_name,
      business_address = excluded.business_address, tax_id = excluded.tax_id,
      payout_method = excluded.payout_method, account_holder_name = excluded.account_holder_name,
      account_number = excluded.account_number, ifsc = excluded.ifsc, upi_id = excluded.upi_id,
      payout_frequency = excluded.payout_frequency, cancellation_policy = excluded.cancellation_policy,
      updated_at = now();
    update coach_profiles set payout_status = 'COMPLETE', updated_at = now() where coach_id = p_coach_id;
  end if;

  update coach_profiles set
    steps_done = (select array_agg(distinct s order by s) from unnest(steps_done || p_step) s),
    current_step = least(5, greatest(current_step, p_step + 1)),
    updated_at = now()
  where coach_id = p_coach_id;
end;
$$;
grant execute on function save_coach_onboarding_step(uuid, integer, jsonb) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Read everything back for resume / review. Payout is masked, and null without the payouts permission.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_coach_onboarding(p_coach_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c coaches;
  p coach_profiles;
  d coach_payout_details;
  v_can boolean;
begin
  select * into c from coaches where id = p_coach_id;
  if c.id is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(c.facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  select * into p from coach_profiles where coach_id = p_coach_id;
  if p.coach_id is null then
    raise exception 'This coach has no onboarding record.' using errcode = 'P0002';
  end if;
  v_can := has_permission(c.facility_id, 'COACHING_MANAGE_COACH_PAYOUTS');
  select * into d from coach_payout_details where coach_id = p_coach_id;

  return jsonb_build_object(
    'coachId', c.id,
    'userId', c.user_id,
    'currentStep', p.current_step,
    'stepsDone', to_jsonb(p.steps_done),
    'onboardingStatus', p.onboarding_status,
    'payoutStatus', p.payout_status,
    'canManagePayouts', v_can,
    'identity', jsonb_build_object(
      'displayName', p.display_name, 'location', p.location, 'timezone', p.timezone,
      'languages', to_jsonb(p.languages), 'shortBio', c.bio, 'dateOfBirth', c.date_of_birth),
    'expertise', jsonb_build_object(
      'niche', p.niche, 'subSpecialties', to_jsonb(p.sub_specialties), 'experienceYears', c.experience_years,
      'targetAudience', to_jsonb(p.target_audience), 'methodology', p.methodology, 'certificates', p.certificates,
      'sportIds', coalesce((select jsonb_agg(cs.facility_sport_id) from coach_sports cs where cs.coach_id = c.id), '[]'::jsonb),
      'expertiseLevels', to_jsonb(c.expertise_levels)),
    'services', jsonb_build_object(
      'sessionFormats', to_jsonb(p.session_formats), 'sessionDurations', to_jsonb(p.session_durations),
      'defaultSessionDurationMinutes', c.default_session_duration_minutes,
      'perSessionRateMinor', p.per_session_rate_minor, 'weeklyRateMinor', p.weekly_rate_minor,
      'monthlyRateMinor', p.monthly_rate_minor,
      'availability', coalesce((select jsonb_agg(jsonb_build_object(
          'dayOfWeek', a.day_of_week, 'startTime', to_char(a.start_time, 'HH24:MI'), 'endTime', to_char(a.end_time, 'HH24:MI'))
          order by a.day_of_week, a.start_time) from coach_availability a where a.coach_id = c.id), '[]'::jsonb)),
    'payout', case when v_can and d.coach_id is not null then jsonb_build_object(
        'entityType', d.entity_type, 'legalName', d.legal_name, 'businessAddress', d.business_address,
        'taxIdMasked', _coach_mask(d.tax_id), 'payoutMethod', d.payout_method,
        'accountHolderName', d.account_holder_name, 'accountNumberMasked', _coach_mask(d.account_number),
        'ifsc', d.ifsc, 'upiId', d.upi_id, 'currency', d.currency,
        'payoutFrequency', d.payout_frequency, 'cancellationPolicy', d.cancellation_policy) end
  );
end;
$$;
grant execute on function get_coach_onboarding(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Step 5: record the agreements and activate the coach. Steps 1-3 must be done; step 4 (KYC) may still be pending.
-- p_legal: terms, ethics, privacy, commission (all must be true)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function complete_coach_onboarding(p_coach_id uuid, p_legal jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c coaches;
  p coach_profiles;
begin
  select * into c from coaches where id = p_coach_id;
  if c.id is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(c.facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  select * into p from coach_profiles where coach_id = p_coach_id for update;
  if p.coach_id is null then
    raise exception 'This coach has no onboarding record.' using errcode = 'P0002';
  end if;
  if not (p.steps_done @> array[1, 2, 3]) then
    raise exception 'Finish steps 1 to 3 before submitting.' using errcode = '22023';
  end if;
  if not (coalesce((p_legal->>'terms')::boolean, false) and coalesce((p_legal->>'ethics')::boolean, false)
          and coalesce((p_legal->>'privacy')::boolean, false) and coalesce((p_legal->>'commission')::boolean, false)) then
    raise exception 'All four agreements must be confirmed.' using errcode = '22023';
  end if;

  update coach_profiles set
    onboarding_status = 'COMPLETE', current_step = 5,
    steps_done = (select array_agg(distinct s order by s) from unnest(steps_done || 5) s),
    legal_accepted_at = now(), legal_accepted_by = auth.uid(), updated_at = now()
  where coach_id = p_coach_id;
  perform update_coach(p_coach_id, null, null, null, null, null, 'ACTIVE', null, null, null, null, null, null);
  perform log_coaching_event(c.facility_id, 'COACH_UPDATED', 'Coach onboarding completed', p_coach_id);
end;
$$;
grant execute on function complete_coach_onboarding(uuid, jsonb) to authenticated;


-- Drafts to resume, for the Coaches list.
create or replace function list_coach_onboarding_drafts(p_facility_id uuid)
returns table (coach_id uuid, full_name text, current_step integer)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  return query
  select cp.coach_id, coalesce(cp.display_name, pr.full_name, 'Coach'), cp.current_step
  from coach_profiles cp
  join coaches c on c.id = cp.coach_id
  left join profiles pr on pr.id = c.user_id
  where cp.facility_id = p_facility_id and cp.onboarding_status = 'DRAFT'
  order by cp.updated_at desc;
end;
$$;
grant execute on function list_coach_onboarding_drafts(uuid) to authenticated;


-- Show the payouts permission as an optional toggle under "Coaching & Coaches" in the role editor.
update access_pages
set extra_keys = array['COACHING_MANAGE_COACH_PAYOUTS']::text[]
where page_key = 'COACHING_OVERVIEW';
