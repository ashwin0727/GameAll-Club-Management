-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the "My Coaching" page (Home → Coaching card, and Coaching when the player is already enrolled).
--
--   get_my_coaching_details()   signed-in player: every ACTIVE or PAUSED coaching enrolment of theirs (found by phone number or login,
--                               like Home), each with everything the page shows — programme, coach, venue, batch / schedule, dates,
--                               progress, fee and payment state, upcoming and past sessions, the payments made and the coach's notes.
--
-- Nothing is stored: it reads coaching_enrollments, coaching_programs, coaching_program_batches, coaches (+ profiles), courts, sports,
-- facilities, coaching_sessions (+ coaching_session_students), student_progress_notes, coaching_enrollment_billing and payments.
--
-- Where the page's numbers come from:
--   sessionsTotal    the enrolment's own session count when the club set one, else every session of the student that is not cancelled
--   sessionsAttended sessions of the student that were COMPLETED (clubs do not record per-student attendance yet, so a completed
--                    session of a batch the student is in counts as attended)
--   progressPercent  attended / total, or — with no sessions yet — how far through its dates the enrolment is
--   payState         PAID | PENDING | FAILED, the same rule as get_my_payment_receipt (0181)
--   rating           the coach's own rating when the club has one, else null (reviews are not counted in GameAll, so none is shown)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_my_coaching_details()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  pl as (select p.id, p.phone from players p, me where p.id = me.uid),
  my_members as (
    select m.id from members m, pl where normalize_phone(m.phone) = pl.phone
    union
    select m.id from members m, me where m.user_id = me.uid
  ),
  mine as (
    select e.*, cp.name as program_name, cp.level as program_level, cp.program_type, cp.sessions_per_week,
           cp.default_capacity as program_capacity, cp.description as program_description,
           coalesce(fs.custom_sport_name, sp.name) as sport_name,
           f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce(f.timezone, 'Asia/Kolkata') as tz,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1),
                    f.hero_image_url) as venue_image,
           b.name as batch_name, b.days_of_week as batch_days, b.start_time as batch_start, b.end_time as batch_end,
           b.capacity as batch_capacity, bc.name as batch_court,
           (select bl.status from coaching_enrollment_billing bl where bl.enrollment_id = e.id) as bill_status,
           (select bl.amount_minor from coaching_enrollment_billing bl where bl.enrollment_id = e.id) as bill_amount,
           co.id as the_coach_id, co.rating as coach_rating, co.certifications, co.experience_years, co.specialization, co.bio,
           pr.full_name as coach_name, pr.avatar_url as coach_avatar
      from coaching_enrollments e
      join coaching_programs cp on cp.id = e.program_id
      join facilities f on f.id = e.facility_id
      left join facility_sports fs on fs.id = cp.facility_sport_id
      left join sports sp on sp.id = fs.sport_id
      left join coaching_program_batches b on b.id = e.batch_id
      left join courts bc on bc.id = b.court_id
      left join coaches co on co.id = coalesce(e.coach_id, b.coach_id)
      left join profiles pr on pr.id = co.user_id
     where e.member_id in (select id from my_members)
       and e.status in ('ACTIVE', 'PAUSED')
  ),
  -- every session of each enrolment: the ones the student is on the roster of, or the batch's own sessions inside the enrolment's dates
  sess as (
    select m.id as enrollment_id, cs.id, cs.start_at, cs.end_at, cs.status, cs.court_id, c.name as court_name
      from mine m
      join coaching_sessions cs on cs.facility_id = m.facility_id
      left join courts c on c.id = cs.court_id
     where exists (select 1 from coaching_session_students s where s.session_id = cs.id and s.enrollment_id = m.id and s.status = 'ENROLLED')
        or (m.batch_id is not null and cs.batch_id = m.batch_id
            and (cs.start_at at time zone m.tz)::date between m.start_date and coalesce(m.end_date, date '9999-12-31')
            and not exists (select 1 from coaching_session_students s where s.session_id = cs.id and s.enrollment_id = m.id and s.status = 'REMOVED'))
  ),
  pay as (
    select m.id as enrollment_id,
           coalesce((select sum(p.amount_inr) from payments p where p.coaching_enrollment_id = m.id and p.status = 'paid'), 0) as paid_inr,
           exists (select 1 from payments p where p.coaching_enrollment_id = m.id and p.status = 'failed') as has_failed
      from mine m
  )
  select coalesce(jsonb_agg(d.j order by d.start_date, d.created_at), '[]'::jsonb)
  from (
    select m.start_date, m.created_at,
      jsonb_build_object(
        'id', m.id,
        'enrollmentRef', 'CRS-' || upper(left(coalesce(nullif(regexp_replace(m.venue_name, '[^A-Za-z]', '', 'g'), ''), 'GAM'), 3)) || '-' || upper(substr(replace(m.id::text, '-', ''), 1, 6)),
        'status', m.status,
        'programName', m.program_name,
        'level', m.program_level,
        'sport', m.sport_name,
        'programType', m.program_type,
        'description', nullif(trim(coalesce(m.program_description, '')), ''),
        'sessionsPerWeek', m.sessions_per_week,
        'startDate', m.start_date,
        'endDate', m.end_date,
        'feeType', m.fee_type,
        'venue', jsonb_build_object('id', m.facility_id, 'name', m.venue_name, 'area', m.venue_area, 'city', m.venue_city,
                                    'phone', nullif(trim(coalesce(m.venue_phone, '')), ''), 'imageUrl', m.venue_image),
        'coach', case when m.the_coach_id is null then null else jsonb_build_object(
                   'id', m.the_coach_id, 'name', m.coach_name, 'avatarUrl', m.coach_avatar,
                   'certification', nullif(trim(coalesce(m.certifications, m.specialization, '')), ''),
                   'experienceYears', m.experience_years, 'bio', nullif(trim(coalesce(m.bio, '')), ''), 'rating', m.coach_rating, 'reviews', null) end,
        'batch', case when m.batch_id is null then null else jsonb_build_object(
                   'name', m.batch_name, 'daysOfWeek', to_jsonb(m.batch_days),
                   'startTime', to_char(m.batch_start, 'HH24:MI'), 'endTime', to_char(m.batch_end, 'HH24:MI'),
                   'capacity', coalesce(m.batch_capacity, m.program_capacity), 'court', m.batch_court) end,
        'progress', (
          select jsonb_build_object(
            'sessionsTotal', coalesce(m.sessions_total, nullif(count(*) filter (where s.status <> 'CANCELLED'), 0)),
            'sessionsAttended', count(*) filter (where s.status = 'COMPLETED'),
            'percent', case
                         when coalesce(m.sessions_total, nullif(count(*) filter (where s.status <> 'CANCELLED'), 0)) is not null
                           then least(100, round(100.0 * count(*) filter (where s.status = 'COMPLETED')
                                                   / coalesce(m.sessions_total, nullif(count(*) filter (where s.status <> 'CANCELLED'), 0))))
                         when m.end_date is not null and m.end_date > m.start_date
                           then greatest(0, least(100, round(100.0 * ((now() at time zone m.tz)::date - m.start_date) / (m.end_date - m.start_date))))
                         else 0 end)
            from sess s where s.enrollment_id = m.id),
        'totalInr', m.price_minor / 100,
        'chargeInr', coalesce(case when m.fee_type = 'MONTHLY' then m.bill_amount end, m.price_minor) / 100,
        'paidInr', py.paid_inr,
        'payState', case
                      when m.bill_status in ('HALTED', 'PENDING', 'EXPIRED', 'CANCELLED') then 'FAILED'
                      when m.price_minor <= 0 or py.paid_inr >= m.price_minor / 100.0 or m.bill_status in ('AUTHENTICATED', 'ACTIVE', 'PAID', 'COMPLETED') then 'PAID'
                      when py.has_failed then 'FAILED'
                      else 'PENDING' end,
        'upcoming', coalesce((
          select jsonb_agg(jsonb_build_object('id', s.id, 'startTime', s.start_at, 'endTime', s.end_at, 'status', s.status, 'court', s.court_name) order by s.start_at)
            from (select * from sess x where x.enrollment_id = m.id and x.start_at >= now() and x.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
                   order by x.start_at limit 6) s), '[]'::jsonb),
        'past', coalesce((
          select jsonb_agg(jsonb_build_object('id', s.id, 'startTime', s.start_at, 'endTime', s.end_at, 'status', s.status, 'court', s.court_name) order by s.start_at desc)
            from (select * from sess x where x.enrollment_id = m.id and (x.start_at < now() or x.status in ('COMPLETED', 'CANCELLED'))
                   order by x.start_at desc limit 40) s), '[]'::jsonb),
        'payments', coalesce((
          select jsonb_agg(jsonb_build_object('id', p.id, 'amountInr', p.amount_inr, 'status', p.status::text, 'method', p.payment_method,
                                              'paidAt', p.paid_at, 'reference', coalesce(p.reference, p.razorpay_payment_id)) order by p.paid_at desc nulls last)
            from payments p where p.coaching_enrollment_id = m.id), '[]'::jsonb),
        'notes', coalesce((
          select jsonb_agg(jsonb_build_object('id', n.id, 'note', n.note, 'skill', n.skill_or_goal, 'progress', n.progress_status, 'createdAt', n.created_at,
                                              'coach', (select pr2.full_name from coaches c2 join profiles pr2 on pr2.id = c2.user_id where c2.id = n.coach_id))
                           order by n.created_at desc)
            from (select * from student_progress_notes x where x.enrollment_id = m.id order by x.created_at desc limit 30) n), '[]'::jsonb)
      ) as j
    from mine m
    join pay py on py.enrollment_id = m.id
  ) d;
$$;
revoke all on function get_my_coaching_details() from public, anon;
grant execute on function get_my_coaching_details() to authenticated;
