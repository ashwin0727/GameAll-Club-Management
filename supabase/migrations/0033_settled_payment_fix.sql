-- ═══════════════════════════════════════════════════════════════════════════
-- Settled-payment status fix — Phase 8.1.
--
-- 0032 checked for a settled payment inside a "current cycle" window
-- (end_date - duration_days). That breaks a recurring membership whose
-- Razorpay cadence (monthly) differs from its own duration_days (e.g. a
-- 1-year membership billed monthly): each subscription.charged rolls
-- end_date forward, pushing the window past the payment's date, so a real
-- payment reads as unsettled.
--
-- The window served no purpose the paid-through date (end_date) doesn't
-- already cover: if end_date < today the renewal is owed and the status is
-- payment_incomplete anyway. So drop the window — a membership is settled
-- once ANY `paid` payment with paid_at exists.
--
-- Only membership_display_status changes; its three callers
-- (list_memberships / get_membership_page_summary / get_membership_detail)
-- invoke it by name and are untouched.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function membership_display_status(
  p_id uuid,
  p_raw_status text,
  p_start date,
  p_end date,
  p_duration integer,
  p_fee integer
) returns text
language sql
stable
as $$
  select case
    when p_raw_status = 'cancelled' then 'inactive'
    when coalesce(p_fee, 0) = 0 then 'active'
    when p_end < current_date then 'payment_incomplete'
    when not exists (
      select 1 from payments
      where membership_id = p_id and status = 'paid' and paid_at is not null
    ) then 'payment_incomplete'
    else 'active'
  end;
$$;

-- get_membership_detail still calls membership_is_settled for the payment
-- "settled" flag it returns — redefine it the same window-free way (the
-- p_cycle_start arg is kept for signature stability but ignored) so that
-- flag stays consistent with the status.
create or replace function membership_is_settled(p_membership_id uuid, p_cycle_start date)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from payments
    where membership_id = p_membership_id and status = 'paid' and paid_at is not null
  );
$$;