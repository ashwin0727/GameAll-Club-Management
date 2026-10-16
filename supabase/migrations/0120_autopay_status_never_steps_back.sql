-- ═══════════════════════════════════════════════════════════════════════════
-- AutoPay status must never step BACK.
--
-- apply_subscription_webhook allowed "active <-> pending" in both directions, but its guard was written so
-- that ANY status was accepted while the subscription was active or pending — including "authenticated".
-- Razorpay does not always deliver events in order, so a late subscription.authenticated arriving after
-- subscription.charged moved a charging subscription back to "authenticated": the member detail page then
-- said "Authorised" with a charge already collected and hid the next payment date.
--
-- Fixed here, and the rows already left on the earlier status are repaired.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function apply_subscription_webhook(
  p_razorpay_subscription_id text,
  p_status membership_subscription_status,
  p_charge_count integer default null,
  p_current_start date default null,
  p_current_end date default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sub membership_subscriptions;
  v_status membership_subscription_status;
  rank_map jsonb := '{"created":0,"authenticated":1,"active":2,"pending":2,"halted":3,"cancelled":4,"completed":4}';
begin
  select * into sub from membership_subscriptions
    where razorpay_subscription_id = p_razorpay_subscription_id;
  if sub.id is null then
    -- A subscription Razorpay knows about that we don't — nothing to do.
    return;
  end if;

  update membership_subscriptions
    set status = case
          -- a stopped subscription stays stopped
          when sub.status in ('cancelled', 'completed') then sub.status
          -- a charging / retrying one never goes back to created / authenticated (late, out-of-order events)
          when sub.status in ('active', 'pending') and p_status in ('created', 'authenticated') then sub.status
          -- otherwise only move forward (active <-> pending is the one sideways move)
          when (rank_map ->> sub.status::text)::int > (rank_map ->> p_status::text)::int
               and sub.status not in ('active', 'pending') then sub.status
          else p_status
        end,
        charge_count = coalesce(p_charge_count, charge_count),
        current_start = coalesce(p_current_start, current_start),
        current_end = coalesce(p_current_end, current_end),
        updated_at = now()
    where id = sub.id
    returning status into v_status;

  -- AutoPay is "on" while the mandate is authorised and charging; off once it has stopped.
  update memberships
    set auto_renew = (v_status in ('authenticated', 'active', 'pending'))
    where id = sub.membership_id;
end;
$$;

revoke execute on function apply_subscription_webhook(text, membership_subscription_status, integer, date, date) from public, anon, authenticated;
grant execute on function apply_subscription_webhook(text, membership_subscription_status, integer, date, date) to service_role;

-- Repair: subscriptions that already collected a charge but were moved back to authenticated / created.
update membership_subscriptions s
   set status = 'active', updated_at = now()
 where s.status in ('authenticated', 'created')
   and exists (
     select 1 from payments p
      where p.membership_id = s.membership_id and p.payment_method = 'upi_autopay' and p.status = 'paid'
   );

update memberships m
   set auto_renew = true
 where exists (
     select 1 from membership_subscriptions s
      where s.membership_id = m.id and s.status in ('authenticated', 'active', 'pending')
   )
   and m.auto_renew is distinct from true;
