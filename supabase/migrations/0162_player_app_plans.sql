-- Player App: what each plan gives players.
--
--   Basic     the club is visible to players and they can book guest slots, but not enrol in memberships
--   Advanced  players can also enrol in the club's memberships themselves
--
-- Enforced where players join: public_start_membership_signup refuses a club whose plan lacks PLAYER_MEMBERSHIPS, and
-- public_facility_accepts_memberships lets the join page say so up front instead of failing at the last step.

update plans set feature_flags = array['AUTOPAY', 'PLAYER_MEMBERSHIPS'] where code = 'advanced';

update plans set features = array[
  'Today / Home and Calendar', 'Tournaments management', 'Guest booking',
  'Player App: your club is visible and players can book guest slots',
  'Memberships: manual payment tracking (plan and schedule)', 'Coaching: manual payment tracking (programs and students)',
  'Reports and analytics', 'Next-day (T+1) payouts'
] where code = 'basic';

update plans set features = array[
  'Everything in Basic', 'Guest player lists',
  'Player App: players can also enrol in your memberships themselves',
  'Memberships: automatic payment tracking', 'Coaching: automatic payment tracking, with schedule',
  'Maintenance management', 'Staff management', 'Finance management', 'Payouts within 5 minutes'
] where code = 'advanced';

-- Does this club take online (player-initiated) membership sign-ups? Public: the join page asks before showing the form.
create or replace function public_facility_accepts_memberships(p_facility_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$ select plan_has_feature(p_facility_id, 'PLAYER_MEMBERSHIPS'); $$;
grant execute on function public_facility_accepts_memberships(uuid) to anon, authenticated;


create or replace function public_start_membership_signup(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_plan_id uuid,
  p_batch_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan membership_plans;
  batch membership_batches;
  v_member_id uuid;
  computed_end date;
  v_membership_id uuid;
begin
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'Name and phone are required.' using errcode = '22023';
  end if;

  -- Players joining a membership from the Player App / join link is part of the Advanced plan. A club with no plan yet is
  -- unrestricted; Basic clubs take guest bookings only.
  if not plan_has_feature(p_facility_id, 'PLAYER_MEMBERSHIPS') then
    raise exception 'This club is not taking online memberships.' using errcode = '42501';
  end if;

  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
  end if;

  if p_batch_id is not null then
    select * into batch from membership_batches where id = p_batch_id and facility_id = p_facility_id and is_active;
    if batch.id is null then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
  end if;

  select id into v_member_id from members
    where facility_id = p_facility_id and phone = trim(p_phone);
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(p_email), ''))
    returning id into v_member_id;
  end if;

  computed_end := current_date + plan.duration_days;

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_by, monthly_price_inr)
  values (p_facility_id, v_member_id, p_plan_id,
          case when computed_end >= current_date then 'active' else 'expired' end,
          current_date, computed_end, null, plan.price_inr)
  returning id into v_membership_id;

  if p_batch_id is not null then
    perform assign_batch_member(p_batch_id, v_member_id, v_membership_id);
  end if;

  if plan.price_inr > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, v_member_id, v_membership_id, plan.price_inr, 'created');
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id,
    'memberId', v_member_id,
    'amountInr', plan.price_inr
  );
end;
$$;
