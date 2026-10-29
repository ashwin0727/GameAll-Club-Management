-- ═══════════════════════════════════════════════════════════════════════════
-- Fewer, lighter requests.
--
--   get_session_bundle()                  everything an app needs after sign-in in ONE call: profile, facility, role,
--                                         permissions, plan and whether this is the platform admin. Before, the web made
--                                         3–4 calls and the mobile app 6, one after another.
--   list_membership_sessions_for_range()  the calendar needed one request per day on screen (up to 42 for a month view).
--   period_revenue_inr()                  the calendar downloaded every payment row just to add them up.
--   claim_unpushed_notifications()        the notification worker claims its batch atomically, so two overlapping runs can
--                                         never send the same message twice.
--   indexes                               for the queries the notification job runs every minute and the revenue sum.
--
-- All of these only read (or, for the claim, mark) data the caller could already reach; none widens access.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Sign-in bundle ───────────────────────────────────────────────────────────────
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

  -- The person's facility: one they own first, otherwise the oldest one they are an active member of.
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
    'isPlatformAdmin', is_platform_admin()
  );
end;
$$;
grant execute on function get_session_bundle() to authenticated;

-- ── Calendar: membership sessions for a whole range in one call ──────────────────────
create or replace function list_membership_sessions_for_range(p_facility_id uuid, p_from date, p_to date)
returns table (
  batch_id uuid,
  session_id uuid,
  batch_name text,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  session_date date,
  start_time time,
  end_time time,
  capacity integer,
  released_capacity integer,
  member_booked_count integer,
  guest_booked_count integer
) language plpgsql stable security definer set search_path = public
as $$
declare
  d date;
begin
  perform require_page_access_any(p_facility_id, array['MEMBERSHIP_SESSIONS_VIEW', 'BOOKINGS_VIEW', 'MEMBERSHIPS_VIEW']);
  if p_to < p_from or p_to - p_from > 62 then
    raise exception 'Choose a date range of at most two months.' using errcode = '22023';
  end if;
  for d in select generate_series(p_from::timestamp, p_to::timestamp, interval '1 day')::date loop
    return query select * from _list_membership_sessions_for_date_impl(p_facility_id => p_facility_id, p_date => d);
  end loop;
end;
$$;
grant execute on function list_membership_sessions_for_range(uuid, date, date) to authenticated;

-- ── Calendar: money collected in a period, summed in the database ───────────────────
-- Runs as the caller (not security definer), so the payments policy still decides what they may see.
create or replace function period_revenue_inr(p_facility_id uuid, p_from timestamptz, p_to timestamptz)
returns bigint
language sql stable
as $$
  select coalesce(sum(p.amount_inr), 0)::bigint
  from payments p
  where p.facility_id = p_facility_id and p.status::text = 'paid' and p.created_at >= p_from and p.created_at < p_to;
$$;
grant execute on function period_revenue_inr(uuid, timestamptz, timestamptz) to authenticated;

-- ── Notification worker: claim a batch atomically ──────────────────────────────────
-- Marks the rows as pushed in the same statement that returns them. A second run that overlaps the first skips the rows
-- the first already holds (FOR UPDATE SKIP LOCKED), so nobody is notified twice.
create or replace function claim_unpushed_notifications(p_limit integer default 200)
returns table (id uuid, user_id uuid, kind text, title text, body text, data jsonb, created_at timestamptz)
language sql security definer set search_path = public
as $$
  update notifications n
     set pushed_at = now()
   where n.id in (
     select x.id from notifications x
     where x.pushed_at is null
     order by x.created_at
     limit greatest(p_limit, 1)
     for update skip locked
   )
  returning n.id, n.user_id, n.kind, n.title, n.body, n.data, n.created_at;
$$;
revoke all on function claim_unpushed_notifications(integer) from public, anon, authenticated;
grant execute on function claim_unpushed_notifications(integer) to service_role;

-- ── Indexes ─────────────────────────────────────────────────────────────────────────
-- run_notification_jobs() looks for guest bookings that start or end in the next few minutes, across every facility, every minute.
create index if not exists bookings_guest_start_idx on bookings (start_time) where customer_type = 'GUEST' and status = 'confirmed';
create index if not exists bookings_guest_end_idx on bookings (end_time) where customer_type = 'GUEST' and status = 'confirmed';
-- The calendar's revenue sum filters one facility by created_at.
create index if not exists payments_facility_created_at_idx on payments (facility_id, created_at);
-- Memberships are filtered by status per facility (counts, lists).
create index if not exists memberships_facility_status_idx on memberships (facility_id, status);
