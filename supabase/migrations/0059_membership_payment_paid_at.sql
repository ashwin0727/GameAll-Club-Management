-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: a "Paid" membership still reads as payment-incomplete
--
-- create_membership_full inserts the payment row with status = 'paid' but
-- never sets paid_at. membership_is_settled() requires
-- `status = 'paid' AND paid_at IS NOT NULL`, so a membership taken with
-- payment mode PAID shows as "Unpaid" in the list.
--
-- A payment that is 'paid' always has a moment it was paid — enforce that
-- with a trigger, and backfill the rows already affected.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function set_payment_paid_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'paid' and new.paid_at is null then
    new.paid_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists payments_set_paid_at on payments;
create trigger payments_set_paid_at
  before insert or update on payments
  for each row
  execute function set_payment_paid_at();

update payments
set paid_at = coalesce(paid_at, updated_at, created_at)
where status = 'paid' and paid_at is null;
