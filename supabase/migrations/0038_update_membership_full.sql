-- ═══════════════════════════════════════════════════════════════════════════
-- Edit Membership — the Membership Details "Edit" button now reopens the full
-- Create Membership form in edit mode. This adds:
--   • update_membership_full  — edits the member + membership + reserved court
--     time slot in one call. NO payment side-effects (payment is not edited
--     from this screen).
--   • get_membership_detail    — the slot object gains batchId / courtId /
--     facilitySportId / capacity so the form can prefill the slot picker.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function update_membership_full(
  p_membership_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_date_of_birth date,
  p_gender text,
  p_address text,
  p_name text,
  p_membership_type text,
  p_max_family_members integer,
  p_start_date date,
  p_duration_days integer,
  p_description text,
  p_membership_fee_inr integer,
  p_registration_fee_inr integer,
  p_gst_percent numeric,
  p_referral_member_id uuid,
  p_discovery_source text,
  p_notes text,
  p_batch_id uuid default null,
  p_new_batch jsonb default null
) returns memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  m memberships;
  v_member_id uuid;
  computed_end date;
  fee integer := greatest(coalesce(p_membership_fee_inr, 0), 0);
  reg integer := greatest(coalesce(p_registration_fee_inr, 0), 0);
  gst numeric := greatest(coalesce(p_gst_percent, 0), 0);
  gst_amount integer;
  total integer;
  result memberships;
  v_cur_batch_id uuid;
  v_batch_id uuid;
  v_court courts;
  v_days smallint[];
  v_start time;
  v_end time;
  v_capacity integer;
  v_batch_name text;
begin
  select * into m from memberships where id = p_membership_id;
  if m.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(m.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if trim(coalesce(p_full_name, '')) = '' or trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member name and phone are required.' using errcode = '23514';
  end if;
  if coalesce(p_duration_days, 0) <= 0 then
    raise exception 'Choose a membership duration.' using errcode = '23514';
  end if;
  if p_batch_id is not null and p_new_batch is not null then
    raise exception 'Pick one time slot, not both.' using errcode = '23514';
  end if;

  v_member_id := m.member_id;

  -- Member — overwrite with the edited values (unlike create's coalesce merge).
  update members set
    full_name = trim(p_full_name),
    phone = trim(p_phone),
    email = nullif(trim(p_email), ''),
    date_of_birth = p_date_of_birth,
    gender = nullif(trim(p_gender), ''),
    address = nullif(trim(p_address), ''),
    updated_at = now()
  where id = v_member_id;

  computed_end := p_start_date + p_duration_days;
  gst_amount := round(fee * gst / 100.0);
  total := fee + gst_amount + reg;

  update memberships set
    name = nullif(trim(p_name), ''),
    membership_type = coalesce(nullif(trim(p_membership_type), ''), 'INDIVIDUAL'),
    max_family_members = greatest(coalesce(p_max_family_members, 1), 1),
    start_date = p_start_date,
    end_date = computed_end,
    duration_days = p_duration_days,
    description = nullif(trim(p_description), ''),
    membership_fee_inr = fee,
    registration_fee_inr = reg,
    gst_percent = gst,
    total_amount_inr = total,
    monthly_price_inr = coalesce(monthly_price_inr, fee),
    referral_member_id = p_referral_member_id,
    discovery_source = nullif(trim(p_discovery_source), ''),
    notes = nullif(trim(p_notes), '')
  where id = p_membership_id
  returning * into result;

  -- ── Reserved court time slot ────────────────────────────────────────────
  select bm.batch_id into v_cur_batch_id
  from membership_batch_members bm
  where bm.membership_id = p_membership_id
  order by bm.created_at
  limit 1;

  if p_new_batch is not null then
    select array_agg(value::smallint) into v_days
      from jsonb_array_elements_text(p_new_batch->'daysOfWeek');
    v_start := (p_new_batch->>'startTime')::time;
    v_end := (p_new_batch->>'endTime')::time;
    v_capacity := (p_new_batch->>'capacity')::integer;

    if v_start is null or v_end is null then
      raise exception 'Time slot start and end are required.' using errcode = '23514';
    end if;
    if coalesce(array_length(v_days, 1), 0) = 0 or not (v_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]) then
      raise exception 'Select at least one valid access day for the time slot.' using errcode = '23514';
    end if;
    if v_end <= v_start then
      raise exception 'Time slot end must be after the start.' using errcode = '23514';
    end if;
    if coalesce(v_capacity, 0) < 1 then
      raise exception 'Time slot capacity must be at least 1.' using errcode = '23514';
    end if;

    select * into v_court from courts
      where id = (p_new_batch->>'courtId')::uuid
        and facility_id = m.facility_id
        and facility_sport_id = (p_new_batch->>'facilitySportId')::uuid;
    if v_court.id is null then
      raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
    end if;

    v_batch_name := coalesce(
      nullif(trim(p_new_batch->>'name'), ''),
      coalesce(nullif(trim(p_name), ''), 'Membership') || ' · '
        || to_char(v_start, 'FMHH12:MI') || '–' || to_char(v_end, 'FMHH12:MI AM')
    );

    insert into membership_batches (
      facility_id, plan_id, facility_sport_id, court_id, name,
      days_of_week, start_time, end_time, capacity, is_active
    ) values (
      m.facility_id, null, v_court.facility_sport_id, v_court.id, v_batch_name,
      v_days, v_start, v_end, v_capacity, true
    ) returning id into v_batch_id;

    if v_cur_batch_id is not null then
      perform remove_batch_member(v_cur_batch_id, v_member_id);
    end if;
    perform assign_batch_member(v_batch_id, v_member_id, p_membership_id);

  elsif p_batch_id is not null then
    if v_cur_batch_id is distinct from p_batch_id then
      if not exists (
        select 1 from membership_batches
        where id = p_batch_id and facility_id = m.facility_id and is_active
      ) then
        raise exception 'That time slot is not available.' using errcode = '23503';
      end if;
      if v_cur_batch_id is not null then
        perform remove_batch_member(v_cur_batch_id, v_member_id);
      end if;
      perform assign_batch_member(p_batch_id, v_member_id, p_membership_id);
    end if;

  else
    -- Slot cleared.
    if v_cur_batch_id is not null then
      perform remove_batch_member(v_cur_batch_id, v_member_id);
    end if;
  end if;

  return result;
end;
$$;
grant execute on function update_membership_full(
  uuid, text, text, text, date, text, text, text, text, integer, date, integer,
  text, integer, integer, numeric, uuid, text, text, uuid, jsonb
) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_detail — slot object gains the ids the edit form needs.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_detail(p_membership_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  m memberships;
  mem members;
  mp membership_plans;
  pay payments;
  ref_name text;
  creator_name text;
  slot_batch membership_batches;
  slot_court text;
  fee integer;
  settled boolean;
  v_status text;
  timeline jsonb := '[]'::jsonb;
begin
  select * into m from memberships where id = p_membership_id;
  if m.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;

  select * into mem from members where id = m.member_id;
  if m.plan_id is not null then
    select * into mp from membership_plans where id = m.plan_id;
  end if;

  select * into pay from payments
    where membership_id = m.id
    order by coalesce(paid_at, created_at) desc
    limit 1;

  fee := coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0);
  v_status := membership_display_status(m.id, m.status::text, m.start_date, m.end_date, m.duration_days, fee);
  settled := fee = 0 or membership_is_settled(m.id, membership_cycle_start(m.start_date, m.end_date, m.duration_days));

  if m.referral_member_id is not null then
    select full_name into ref_name from members where id = m.referral_member_id;
  end if;
  if m.created_by is not null then
    select full_name into creator_name from profiles where id = m.created_by;
  end if;

  select b.* into slot_batch
  from membership_batch_members bm
  join membership_batches b on b.id = bm.batch_id
  where bm.membership_id = m.id
  order by bm.created_at
  limit 1;
  if slot_batch.id is not null then
    select name into slot_court from courts where id = slot_batch.court_id;
  end if;

  timeline := timeline || jsonb_build_object(
    'label', 'Membership created',
    'actor', coalesce(creator_name, 'Self registered'),
    'at', m.created_at
  );
  if pay.id is not null and pay.paid_at is not null then
    timeline := timeline || jsonb_build_object(
      'label', 'Payment received',
      'actor', coalesce(pay.payment_method, 'Payment'),
      'at', pay.paid_at
    );
  end if;
  if v_status = 'active' and fee > 0 then
    timeline := timeline || jsonb_build_object(
      'label', 'Membership activated',
      'actor', 'System',
      'at', coalesce(pay.paid_at, m.created_at)
    );
  end if;

  return jsonb_build_object(
    'membershipId', m.id,
    'facilityId', m.facility_id,
    'displayStatus', v_status,
    'member', jsonb_build_object(
      'id', mem.id,
      'fullName', mem.full_name,
      'phone', mem.phone,
      'email', mem.email,
      'dateOfBirth', mem.date_of_birth,
      'gender', mem.gender,
      'address', mem.address,
      'status', mem.status,
      'memberSince', mem.created_at
    ),
    'membership', jsonb_build_object(
      'name', coalesce(m.name, mp.name, 'Membership'),
      'membershipType', m.membership_type,
      'rawStatus', m.status,
      'startDate', m.start_date,
      'endDate', m.end_date,
      'durationDays', m.duration_days,
      'maxFamilyMembers', m.max_family_members,
      'description', m.description,
      'membershipFeeInr', coalesce(m.membership_fee_inr, mp.price_inr, 0),
      'registrationFeeInr', coalesce(m.registration_fee_inr, 0),
      'gstPercent', coalesce(m.gst_percent, 0),
      'totalAmountInr', coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0),
      'monthlyPriceInr', coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0),
      'autoRenew', m.auto_renew,
      'createdAt', m.created_at
    ),
    'payment', case when pay.id is null then null else jsonb_build_object(
      'amountInr', pay.amount_inr,
      'status', pay.status,
      'settled', pay.paid_at is not null,
      'method', pay.payment_method,
      'paidAt', pay.paid_at,
      'createdAt', pay.created_at,
      'transactionId', pay.razorpay_payment_id
    ) end,
    'referralName', ref_name,
    'referralMemberId', m.referral_member_id,
    'createdByName', creator_name,
    'discoverySource', m.discovery_source,
    'paymentReference', m.payment_reference,
    'notes', m.notes,
    'slot', case when slot_batch.id is null then null else jsonb_build_object(
      'batchId', slot_batch.id,
      'courtId', slot_batch.court_id,
      'facilitySportId', slot_batch.facility_sport_id,
      'courtName', slot_court,
      'capacity', slot_batch.capacity,
      'daysOfWeek', slot_batch.days_of_week,
      'startTime', slot_batch.start_time,
      'endTime', slot_batch.end_time
    ) end,
    'timeline', timeline
  );
end;
$$;
grant execute on function get_membership_detail(uuid) to authenticated;