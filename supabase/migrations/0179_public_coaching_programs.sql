-- The Player app's Coaching page: one entry per coaching programme in a city, with its venue, its coach and its batches.
--
-- ONE programme per venue: the one the club created most recently (the Player app opens the enrolment page from it, where every
-- programme of the venue can be chosen). Only ACTIVE programmes that have not finished, at venues that are open (ACTIVE + onboarding COMPLETED) in the picked city. The coach is
-- the one on the programme's first ACTIVE batch (name / photo from the staff profile behind the coach). The price is the programme's
-- base fee less a running early-bird discount (tax is added on the enrolment page, as before). Anyone can call it, no sign-in.
-- Re-runnable (create or replace).
--
-- Each entry: { programId, name, level, description, sport, programType (GROUP | ONE_ON_ONE | TRIAL), feeType (ONE_TIME | MONTHLY),
--               imageUrl, priceMinor, maxCapacity, batches: [{ startTime, endTime, daysOfWeek }], coach: {...} | null,
--               venue: { id, name, area, city, state, heroImageUrl, verified } }
create or replace function list_public_coaching_programs(p_city text, p_state text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with want as (
    select
      case when lower(trim(coalesce(p_city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(p_city, ''))) end as city,
      lower(trim(coalesce(p_state, ''))) as state
  ),
  today as (select (now() at time zone 'Asia/Kolkata')::date as d),
  venues as (
    select f.id, f.name, f.city, f.state, f.area,
           coalesce(
             (select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1),
             f.hero_image_url) as hero_image_url,
           exists (select 1 from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED') as verified
      from facilities f, want w
     where f.status = 'ACTIVE'
       and f.onboarding_step = 'COMPLETED'
       and w.city <> ''
       and (case when lower(trim(coalesce(f.city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(f.city, ''))) end) = w.city
       and (w.state = '' or lower(trim(coalesce(f.state, ''))) in ('', w.state))
  ),
  progs as (
    select cp.id, cp.facility_id, cp.name, cp.level, cp.description, cp.program_type, cp.fee_type, cp.image_url,
           row_number() over (partition by cp.facility_id order by cp.created_at desc, cp.id) as rn,
           coalesce(fs.custom_sport_name, sp.name) as sport_name,
           greatest(
             coalesce(cp.default_price_minor, 0)
             - case when coalesce(cp.early_bird_discount_minor, 0) > 0
                         and (cp.discount_valid_till is null or cp.discount_valid_till >= t.d)
                    then cp.early_bird_discount_minor else 0 end,
             0) as price_minor
      from coaching_programs cp
      cross join today t
      left join facility_sports fs on fs.id = cp.facility_sport_id
      left join sports sp on sp.id = fs.sport_id
     where cp.status = 'ACTIVE'
       and (cp.end_date is null or cp.end_date >= t.d)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'programId', p.id,
      'name', p.name,
      'level', p.level,
      'description', nullif(trim(coalesce(p.description, '')), ''),
      'sport', p.sport_name,
      'programType', p.program_type,
      'feeType', p.fee_type,
      'imageUrl', p.image_url,
      'priceMinor', p.price_minor,
      'maxCapacity', (select max(b.capacity) from coaching_program_batches b where b.program_id = p.id and b.status = 'ACTIVE'),
      'batches', coalesce((
        select jsonb_agg(jsonb_build_object('startTime', b.start_time, 'endTime', b.end_time, 'daysOfWeek', b.days_of_week) order by b.start_time)
          from coaching_program_batches b
         where b.program_id = p.id and b.status = 'ACTIVE'), '[]'::jsonb),
      'coach', (
        select jsonb_build_object(
                 'name', coalesce(nullif(trim(pr.full_name), ''), 'Coach'),
                 'avatarUrl', pr.avatar_url,
                 'certifications', nullif(trim(coalesce(co.certifications, '')), ''),
                 'specialization', nullif(trim(coalesce(co.specialization, '')), ''),
                 'rating', co.rating,
                 'experienceYears', co.experience_years)
          from coaching_program_batches b
          join coaches co on co.id = b.coach_id and co.status = 'ACTIVE'
          left join profiles pr on pr.id = co.user_id
         where b.program_id = p.id and b.status = 'ACTIVE'
         order by b.start_time
         limit 1),
      'venue', jsonb_build_object(
        'id', v.id, 'name', v.name, 'area', v.area, 'city', v.city, 'state', v.state,
        'heroImageUrl', v.hero_image_url, 'verified', v.verified)
    ) order by v.name, p.name
  ), '[]'::jsonb)
  from progs p
  join venues v on v.id = p.facility_id
 where p.rn = 1;
$$;
revoke all on function list_public_coaching_programs(text, text) from public;
grant execute on function list_public_coaching_programs(text, text) to anon, authenticated;
