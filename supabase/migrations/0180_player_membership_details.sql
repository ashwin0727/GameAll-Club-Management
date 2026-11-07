-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the "Membership Details" page (Home → My Membership).
--
--   get_my_membership_details()   signed-in player: every ACTIVE membership of theirs (matched by phone number or login, like Home),
--                                 each with everything the page shows — plan, venue, allocated court / time slot, valid dates, the
--                                 membership id, this month's usage, payments, bookings, benefits and the payment state.
--
-- Nothing is stored: it only reads memberships, membership_plans, membership_batches (+ roster), courts, sports, facilities, payments,
-- membership_subscriptions, bookings and membership_session_bookings.
--
-- Usage ("This Month's Usage 12 / 20 Sessions"):
--   sessionsTotal = how many days this month the allocated slot runs (the batch's weekdays, inside the membership's own dates)
--   sessionsUsed  = distinct days up to today on which the member played: a court booking of theirs (not cancelled) or a confirmed
--                   membership session booking
-- membershipRef ("MBR-CHZ-000458") = MBR - first three letters of the venue name - the membership's number at that venue (by creation order).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_my_membership_details()
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
  clock as (
    select (now() at time zone 'Asia/Kolkata')::date as today,
           date_trunc('month', now() at time zone 'Asia/Kolkata')::date as month_start,
           (date_trunc('month', now() at time zone 'Asia/Kolkata') + interval '1 month - 1 day')::date as month_end
  ),
  mine as (
    select ms.*, f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1),
                    f.hero_image_url) as venue_image,
           (select count(*) from memberships x where x.facility_id = ms.facility_id and (x.created_at, x.id) <= (ms.created_at, ms.id)) as venue_seq
      from memberships ms
      join facilities f on f.id = ms.facility_id
     where ms.member_id in (select id from my_members)
       and ms.status::text = 'active'
       and ms.end_date >= (select today from clock)
  )
  select coalesce(jsonb_agg(d.j order by d.end_date, d.created_at), '[]'::jsonb)
  from (
    select m.end_date, m.created_at,
      jsonb_build_object(
        'id', m.id,
        'membershipRef', 'MBR-' || upper(left(coalesce(nullif(regexp_replace(m.venue_name, '[^A-Za-z]', '', 'g'), ''), 'GAM'), 3)) || '-' || lpad(m.venue_seq::text, 6, '0'),
        'status', m.status::text,
        'planName', coalesce(nullif(trim(m.name), ''), mp.name, 'Membership'),
        'description', coalesce(nullif(trim(m.description), ''), nullif(trim(mp.description), '')),
        'planType', mp.plan_type::text,
        'category', mp.category,
        'badge', mp.badge_text,
        'durationDays', coalesce(m.duration_days, mp.duration_days),
        'priceInr', coalesce(m.membership_fee_inr, mp.price_inr),
        'registrationFeeInr', coalesce(m.registration_fee_inr, 0),
        'totalInr', m.total_amount_inr,
        'features', coalesce(to_jsonb(mp.features), '[]'::jsonb),
        'startDate', m.start_date,
        'endDate', m.end_date,
        'memberSince', (select min(x.start_date) from memberships x where x.member_id = m.member_id and x.facility_id = m.facility_id),
        'autoRenew', m.auto_renew,
        'autopayStatus', (select s.status::text from membership_subscriptions s where s.membership_id = m.id),
        'paymentMethod', (select p.payment_method from payments p where p.membership_id = m.id and p.status = 'paid' order by p.paid_at desc nulls last limit 1),
        'payState', case
            when (select s.status::text from membership_subscriptions s where s.membership_id = m.id) in ('halted', 'pending') then 'FAILED'
            when coalesce(m.total_amount_inr, 0) <= 0
              or coalesce((select sum(p.amount_inr) from payments p where p.membership_id = m.id and p.status = 'paid'), 0) >= m.total_amount_inr
              or (select s.status::text from membership_subscriptions s where s.membership_id = m.id) in ('authenticated', 'active', 'completed') then 'PAID'
            when exists (select 1 from payments p where p.membership_id = m.id and p.status = 'failed') then 'FAILED'
            else 'PENDING' end,
        'paidInr', coalesce((select sum(p.amount_inr) from payments p where p.membership_id = m.id and p.status = 'paid'), 0),
        'venue', jsonb_build_object('id', m.facility_id, 'name', m.venue_name, 'area', m.venue_area, 'city', m.venue_city,
                                    'phone', nullif(trim(coalesce(m.venue_phone, '')), ''), 'imageUrl', m.venue_image),
        'slot', (
          select jsonb_build_object('batchName', b.name, 'sport', b.sport, 'court', b.court, 'daysOfWeek', to_jsonb(b.days_of_week),
                                    'startTime', to_char(b.start_time, 'HH24:MI'), 'endTime', to_char(b.end_time, 'HH24:MI'))
            from (
              select mb.name, mb.days_of_week, mb.start_time, mb.end_time, c.name as court, coalesce(fs.custom_sport_name, sp.name) as sport
                from membership_batch_members bm
                join membership_batches mb on mb.id = bm.batch_id and mb.is_active
                left join courts c on c.id = mb.court_id
                left join facility_sports fs on fs.id = mb.facility_sport_id
                left join sports sp on sp.id = fs.sport_id
               where bm.member_id = m.member_id and (bm.membership_id = m.id or bm.membership_id is null)
               order by (bm.membership_id = m.id) desc, bm.created_at desc
               limit 1
            ) b),
        'usage', (
          select jsonb_build_object(
                   'monthStart', c.month_start, 'monthEnd', c.month_end,
                   'sessionsTotal', case when b.days_of_week is null then null else (
                       select count(*) from generate_series(greatest(c.month_start, m.start_date), least(c.month_end, m.end_date), interval '1 day') g(d)
                        where extract(dow from g.d)::smallint = any (b.days_of_week)) end,
                   'sessionsUsed', (
                       select count(distinct u.day) from (
                         select (bk.start_time at time zone 'Asia/Kolkata')::date as day
                           from bookings bk
                          where bk.member_id = m.member_id and bk.facility_id = m.facility_id and bk.status::text in ('confirmed', 'completed')
                            and (bk.start_time at time zone 'Asia/Kolkata')::date between c.month_start and c.today
                         union
                         select s.session_date
                           from membership_session_bookings sb join membership_sessions s on s.id = sb.session_id
                          where sb.member_id = m.member_id and sb.facility_id = m.facility_id and sb.status = 'CONFIRMED'
                            and s.session_date between c.month_start and c.today
                       ) u))
            from clock c
            left join lateral (
              select mb.days_of_week
                from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id and mb.is_active
               where bm.member_id = m.member_id and (bm.membership_id = m.id or bm.membership_id is null)
               order by (bm.membership_id = m.id) desc, bm.created_at desc limit 1
            ) b on true),
        'payments', coalesce((
          select jsonb_agg(jsonb_build_object('id', p.id, 'amountInr', p.amount_inr, 'status', p.status::text, 'method', p.payment_method,
                                              'paidAt', p.paid_at, 'createdAt', p.created_at, 'reference', coalesce(p.reference, p.razorpay_payment_id))
                           order by coalesce(p.paid_at, p.created_at) desc)
            from payments p where p.membership_id = m.id), '[]'::jsonb),
        'bookings', coalesce((
          select jsonb_agg(jsonb_build_object('id', r.id, 'startTime', r.start_time, 'endTime', r.end_time, 'status', r.status, 'court', r.court,
                                              'sport', r.sport, 'source', r.source) order by r.start_time desc)
            from (
              select * from (
                select bk.id, bk.start_time, bk.end_time, bk.status::text as status, c.name as court, coalesce(fs.custom_sport_name, sp.name) as sport, 'BOOKING' as source
                  from bookings bk
                  left join courts c on c.id = bk.court_id
                  left join facility_sports fs on fs.id = c.facility_sport_id
                  left join sports sp on sp.id = c.sport_id
                 where bk.member_id = m.member_id and bk.facility_id = m.facility_id
                union all
                select sb.id, (s.session_date + s.start_time) at time zone 'Asia/Kolkata', (s.session_date + s.end_time) at time zone 'Asia/Kolkata',
                       lower(sb.status), c.name, coalesce(fs.custom_sport_name, sp.name), 'SESSION'
                  from membership_session_bookings sb
                  join membership_sessions s on s.id = sb.session_id
                  left join courts c on c.id = s.court_id
                  left join facility_sports fs on fs.id = s.facility_sport_id
                  left join sports sp on sp.id = fs.sport_id
                 where sb.member_id = m.member_id and sb.facility_id = m.facility_id
              ) all_rows
              order by start_time desc
              limit 40
            ) r), '[]'::jsonb)
      ) as j
    from mine m
    left join membership_plans mp on mp.id = m.plan_id
  ) d;
$$;
revoke all on function get_my_membership_details() from public, anon;
grant execute on function get_my_membership_details() to authenticated;
