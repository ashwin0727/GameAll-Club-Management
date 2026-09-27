-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: add_coach rejects a brand-new staff member created via the Add Coach
-- wizard's own "+ New person" path with "That person is not an active staff
-- member of this facility."
--
-- create-staff (the edge function) deliberately gives a genuinely new person
-- facility_users.status = 'INVITED', not 'ACTIVE' — they get a one-time
-- password and must reset it before they've ever signed in (0073's own status
-- enum: 'ACTIVE' | 'INACTIVE' | 'INVITED'). add_coach's check required
-- status = 'ACTIVE' specifically, so the wizard's own "create the staff
-- account, then make them a coach" flow — the one thing this feature exists
-- to support — failed immediately on every truly-new person.
--
-- INVITED is a legitimate, current staff member (just mid-onboarding); only
-- INACTIVE (removed/deactivated) should be rejected. Same relaxation applied
-- to list_coach_candidates so an invited-but-not-yet-signed-in staff member
-- is still pickable as an existing candidate.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function add_coach(
  p_facility_id uuid,
  p_user_id uuid,
  p_specialization text default null,
  p_experience_years numeric default null,
  p_certifications text default null,
  p_bio text default null,
  p_hourly_rate_minor integer default null,
  p_status text default 'ACTIVE',
  p_joined_on date default null,
  p_sport_ids uuid[] default null,
  p_expertise_levels text[] default null,
  p_default_session_duration_minutes integer default null,
  p_date_of_birth date default null
) returns coaches
language plpgsql
security definer
set search_path = public
as $$
declare result coaches;
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from facility_users
    where facility_id = p_facility_id and user_id = p_user_id and status <> 'INACTIVE'
  ) then
    raise exception 'That person is not a staff member of this facility. Add them as staff first.' using errcode = '23503';
  end if;
  if coalesce(p_status, 'ACTIVE') not in ('ACTIVE', 'INACTIVE', 'ON_LEAVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;
  if p_default_session_duration_minutes is not null and p_default_session_duration_minutes <= 0 then
    raise exception 'Default session duration must be a positive number of minutes.' using errcode = '22023';
  end if;

  insert into coaches (
    facility_id, user_id, specialization, experience_years, certifications, bio,
    hourly_rate_minor, status, joined_on, created_by, expertise_levels, default_session_duration_minutes,
    date_of_birth
  ) values (
    p_facility_id, p_user_id,
    nullif(trim(coalesce(p_specialization, '')), ''), p_experience_years,
    nullif(trim(coalesce(p_certifications, '')), ''), nullif(trim(coalesce(p_bio, '')), ''),
    p_hourly_rate_minor, coalesce(p_status, 'ACTIVE'), coalesce(p_joined_on, current_date), auth.uid(),
    coalesce(p_expertise_levels, '{}'), p_default_session_duration_minutes, p_date_of_birth
  )
  returning * into result;

  if p_sport_ids is not null and array_length(p_sport_ids, 1) > 0 then
    insert into coach_sports (coach_id, facility_id, facility_sport_id)
    select result.id, p_facility_id, s from unnest(p_sport_ids) as s;
  end if;

  perform log_coaching_event(p_facility_id, 'COACH_CREATED',
    'Coach profile added', result.id, null, null, null,
    jsonb_build_object('userId', p_user_id));
  return result;
exception when unique_violation then
  raise exception 'This staff member already has a coaching profile.' using errcode = '23505';
end;
$$;

grant execute on function add_coach(uuid, uuid, text, numeric, text, text, integer, text, date, uuid[], text[], integer, date) to authenticated;


-- Active staff members who don't yet have a coaching profile — the Add Coach
-- picker. An INVITED (not yet signed in) staff member is still a legitimate
-- candidate; only INACTIVE (removed) staff are excluded.
drop function if exists list_coach_candidates(uuid);

create function list_coach_candidates(p_facility_id uuid)
returns table (user_id uuid, full_name text, email text, phone text, avatar_url text, title text)
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
  select fu.user_id, pr.full_name, pr.email, pr.phone, pr.avatar_url, fu.title
  from facility_users fu
  join profiles pr on pr.id = fu.user_id
  where fu.facility_id = p_facility_id
    and fu.status <> 'INACTIVE'
    and not exists (select 1 from coaches c where c.facility_id = p_facility_id and c.user_id = fu.user_id)
  order by pr.full_name;
end;
$$;

grant execute on function list_coach_candidates(uuid) to authenticated;
