-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 5: Overview.
--
-- One row, composed from the dedicated analytics RPCs so the Overview page
-- makes a single round trip and every headline figure equals the one the
-- detail report shows. Nothing is re-derived here.
--
-- Revenue (gross / expenses / net / outstanding / breakdown) is
-- facility+date only — get_finance_summary / get_revenue_breakdown take no
-- sport/court. Booking counts and utilisation honour the sport/court
-- filter.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_analytics_overview(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  gross_revenue_minor bigint,
  booking_revenue_minor bigint,
  membership_revenue_minor bigint,
  expenses_minor bigint,
  net_revenue_minor bigint,
  outstanding_minor bigint,
  total_bookings bigint,
  completed_bookings bigint,
  cancelled_bookings bigint,
  overall_utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  v_gross bigint;
  v_exp bigint;
  v_net bigint;
  v_out bigint;
  v_membership bigint;
  v_member_book bigint;
  v_guest_book bigint;
  v_total bigint;
  v_completed bigint;
  v_cancelled bigint;
  v_util numeric;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select s.gross_revenue_minor, s.expenses_minor, s.net_revenue_minor, s.outstanding_minor
    into v_gross, v_exp, v_net, v_out
    from get_finance_summary(p_facility_id, p_preset, p_start_date, p_end_date) s;

  select b.membership_revenue_minor, b.member_booking_revenue_minor, b.guest_booking_revenue_minor
    into v_membership, v_member_book, v_guest_book
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date) b;

  select a.total, a.completed, a.cancelled
    into v_total, v_completed, v_cancelled
    from get_booking_analytics(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id
    ) a;

  select u.utilization_pct
    into v_util
    from get_overall_utilization(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id
    ) u;

  return query select
    coalesce(v_gross, 0),
    (coalesce(v_member_book, 0) + coalesce(v_guest_book, 0))::bigint,
    coalesce(v_membership, 0),
    coalesce(v_exp, 0),
    coalesce(v_net, 0),
    coalesce(v_out, 0),
    coalesce(v_total, 0),
    coalesce(v_completed, 0),
    coalesce(v_cancelled, 0),
    coalesce(v_util, 0);
end;
$$;

grant execute on function get_analytics_overview(uuid, text, date, date, uuid, uuid) to authenticated;
