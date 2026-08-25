-- ═══════════════════════════════════════════════════════════════════════════
-- Membership session utilization feed — closes the gap where the Dashboard's
-- Court Utilization only ever looked at `bookings`. A membership session's
-- protected capacity was never in `bookings` at all (it lives in
-- membership_session_bookings, see 0014), so a fully-attended membership
-- court read as 0% utilized.
--
-- Utilization must reflect ACTUAL usage, not allocation: a session with zero
-- confirmed member/guest slots contributes no occupied time (nobody is
-- actually on the court), and a session with at least one confirmed slot
-- occupies its court for its full duration exactly once — the court is
-- shared by however many people showed up, it isn't multiplied per person.
-- ═══════════════════════════════════════════════════════════════════════════

create function get_membership_utilization_sessions(p_facility_id uuid, p_from date, p_to date)
returns table (
  court_id uuid,
  session_date date,
  start_time time,
  end_time time
)
language sql
stable
as $$
  select distinct s.court_id, s.session_date, s.start_time, s.end_time
  from membership_sessions s
  where s.facility_id = p_facility_id
    and s.session_date >= p_from
    and s.session_date < p_to
    and exists (
      select 1 from membership_session_bookings b
      where b.session_id = s.id and b.status = 'CONFIRMED'
    );
$$;

grant execute on function get_membership_utilization_sessions(uuid, date, date) to authenticated;