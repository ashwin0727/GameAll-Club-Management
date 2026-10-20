-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFY the two-year dataset — automatic checks of Finance, Reports, Coaching,
-- Memberships and Pending Payments against the raw tables, plus backward-compatibility
-- calls with the OLD function signatures.
--
-- HOW TO RUN: put the same e-mail you seeded with below, run the whole file.
-- It runs AS that user (the way the app does), inside a transaction that is rolled back,
-- so it changes nothing. The last result grid is the report:
--     first row  = SUMMARY (passed / total)
--     then       = every FAILED check first, then the passes
--
-- Each check compares an "expected" value computed straight from the tables (no app
-- functions) with the "actual" value the app's database function returns.
-- A check that throws an error is reported as a failure with the error text.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

select set_config('request.jwt.claims',
  json_build_object('sub', (select id from profiles where lower(email) = lower('ashwinv277@gmail.com')),   -- ← CHANGE ME
                    'role', 'authenticated')::text, true);
set local role authenticated;

create temp table seed_ctx as
select f.id as fac,
       'Asia/Kolkata'::text as tz,
       date_trunc('month', current_date - interval '27 months')::date as p_start,
       current_date as p_end,
       (date_trunc('month', current_date - interval '27 months')::date::timestamp at time zone 'Asia/Kolkata') as r_from,
       ((current_date + 1)::timestamp at time zone 'Asia/Kolkata') as r_to,
       (select id from facility_sports where facility_id = f.id and sport_id = (select id from sports where key = 'badminton'))  as fs_bad,
       (select id from facility_sports where facility_id = f.id and sport_id = (select id from sports where key = 'pickleball')) as fs_pkl,
       (select id from facility_sports where facility_id = f.id and sport_id = (select id from sports where key = 'cricket'))    as fs_crk
from facilities f
where f.owner_id = (select id from profiles where lower(email) = lower('ashwinv277@gmail.com'))              -- ← CHANGE ME (same e-mail)
order by f.created_at limit 1;

create temp table seed_checks (n serial, area text, test text, expected text, actual text, ok boolean);

create function pg_temp.run(p_area text, p_test text, p_sql text) returns void language plpgsql as $f$
declare e text; a text;
begin
  execute p_sql into e, a;
  insert into seed_checks (area, test, expected, actual, ok) values (p_area, p_test, e, a, e is not distinct from a);
exception when others then
  insert into seed_checks (area, test, expected, actual, ok) values (p_area, p_test, 'no error', 'ERROR: ' || sqlerrm, false);
end $f$;

-- ───────────────────────── 0. the data has the shape we promised ─────────────────────────
select pg_temp.run('0 Dataset', 'one facility found for this e-mail', $q$ select 'true', (select (count(*) = 1)::text from seed_ctx) $q$);
select pg_temp.run('0 Dataset', '3 sports, 5 courts (3 badminton, 1 pickleball, 1 cricket)', $q$
  select '3|5|3|1|1', (select count(*) from facility_sports where facility_id = (select fac from seed_ctx))::text || '|' ||
    (select count(*) from courts where facility_id = (select fac from seed_ctx))::text || '|' ||
    (select count(*) from courts where facility_sport_id = (select fs_bad from seed_ctx))::text || '|' ||
    (select count(*) from courts where facility_sport_id = (select fs_pkl from seed_ctx))::text || '|' ||
    (select count(*) from courts where facility_sport_id = (select fs_crk from seed_ctx))::text $q$);
select pg_temp.run('0 Dataset', 'history is at least 2 years long', $q$
  select 'true', ((select min(start_time)::date from bookings where facility_id = (select fac from seed_ctx)) <= current_date - 730)::text $q$);
select pg_temp.run('0 Dataset', 'at least 1,500 court bookings', $q$ select 'true', ((select count(*) from bookings where facility_id = (select fac from seed_ctx)) >= 1500)::text $q$);
select pg_temp.run('0 Dataset', 'booking mix: completed + cancelled + future confirmed, guest + member', $q$
  select 'true', (
    exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and status = 'completed' and payment_status = 'PAID')
    and exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and status = 'completed' and payment_status = 'PENDING')
    and exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and status = 'cancelled')
    and exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and status = 'confirmed' and start_time > now())
    and exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and customer_type = 'GUEST')
    and exists (select 1 from bookings where facility_id = (select fac from seed_ctx) and customer_type = 'MEMBER'))::text $q$);
select pg_temp.run('0 Dataset', 'memberships: active + expired + cancelled, AutoPay present, some members never given a batch', $q$
  select 'true', (
    exists (select 1 from memberships where facility_id = (select fac from seed_ctx) and status = 'active')
    and exists (select 1 from memberships where facility_id = (select fac from seed_ctx) and status = 'expired')
    and exists (select 1 from memberships where facility_id = (select fac from seed_ctx) and status = 'cancelled')
    and exists (select 1 from membership_subscriptions where facility_id = (select fac from seed_ctx))
    and exists (select 1 from members m where m.facility_id = (select fac from seed_ctx) and m.phone like '77000000%'
                 and not exists (select 1 from membership_batch_members bm where bm.member_id = m.id)))::text $q$);
select pg_temp.run('0 Dataset', 'coaching: active + completed + cancelled enrollments, monthly + one-time + membership-included', $q$
  select 'true', (
    exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and status = 'ACTIVE')
    and exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and status = 'COMPLETED')
    and exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and status = 'CANCELLED')
    and exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and fee_type = 'MONTHLY')
    and exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and fee_type = 'ONE_TIME' and pricing_type = 'STANDARD')
    and exists (select 1 from coaching_enrollments where facility_id = (select fac from seed_ctx) and pricing_type = 'MEMBERSHIP_INCLUDED'))::text $q$);
select pg_temp.run('0 Dataset', 'finance: processed + pending refunds, failed order, expenses paid/part/unpaid, closings', $q$
  select 'true', (
    exists (select 1 from refunds where facility_id = (select fac from seed_ctx) and status = 'PROCESSED')
    and exists (select 1 from refunds where facility_id = (select fac from seed_ctx) and status in ('REQUESTED', 'PENDING'))
    and exists (select 1 from payment_orders where facility_id = (select fac from seed_ctx) and status = 'FAILED')
    and exists (select 1 from expenses where facility_id = (select fac from seed_ctx) and payment_status = 'PAID')
    and exists (select 1 from expenses where facility_id = (select fac from seed_ctx) and payment_status = 'PARTIAL')
    and exists (select 1 from expenses where facility_id = (select fac from seed_ctx) and payment_status = 'PENDING')
    and exists (select 1 from daily_closings where facility_id = (select fac from seed_ctx) and status = 'CLOSED'))::text $q$);

-- ───────────────────────── 1. Finance: all sports ─────────────────────────
select pg_temp.run('1 Finance', 'gross = sum of paid payments', $q$
  select (select (coalesce(sum(p.amount_inr), 0) * 100)::bigint::text from payments p, seed_ctx c
          where p.facility_id = c.fac and p.status = 'paid' and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to),
         (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);
select pg_temp.run('1 Finance', 'refunds = processed refunds', $q$
  select (select coalesce(sum(r.amount_minor), 0)::bigint::text from refunds r, seed_ctx c
          where r.facility_id = c.fac and r.status = 'PROCESSED' and r.processed_at >= c.r_from and r.processed_at < c.r_to),
         (select s.refunds_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);
select pg_temp.run('1 Finance', 'expenses = recorded expenses', $q$
  select (select coalesce(sum(e.amount_minor), 0)::bigint::text from expenses e, seed_ctx c
          where e.facility_id = c.fac and e.status = 'RECORDED' and e.spent_on between c.p_start and c.p_end),
         (select s.expenses_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);
select pg_temp.run('1 Finance', 'net = gross - refunds - expenses', $q$
  select (select (s.gross_revenue_minor - s.refunds_minor - s.expenses_minor)::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select s.net_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);
select pg_temp.run('1 Finance', 'outstanding = unpaid balance of bookings + memberships + coaching', $q$
  with c as (select fac from seed_ctx), o as (
    select coalesce(b.amount_minor, 0)::bigint as tot,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'), 0)::bigint as paid
      from bookings b, c where b.facility_id = c.fac and b.status in ('pending', 'confirmed', 'completed')
    union all
    select (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.membership_id = ms.id and p.status = 'paid'), 0)::bigint
      from memberships ms, c where ms.facility_id = c.fac and ms.status <> 'cancelled'
    union all
    select coalesce(e.price_minor, 0)::bigint,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint
      from coaching_enrollments e, c where e.facility_id = c.fac and e.status <> 'CANCELLED')
  select (select coalesce(sum(tot - paid), 0)::bigint::text from o where tot > 0 and paid < tot),
         (select s.outstanding_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);
select pg_temp.run('1 Finance', 'pending-payments summary = finance summary outstanding', $q$
  select (select s.outstanding_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select s.outstanding_minor::text from seed_ctx c, get_pending_payments_summary(c.fac) s) $q$);
select pg_temp.run('1 Finance', 'revenue breakdown parts add up to gross', $q$
  select (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select (b.membership_revenue_minor + b.member_booking_revenue_minor + b.guest_booking_revenue_minor + b.coaching_revenue_minor)::text
            from seed_ctx c, get_revenue_breakdown(c.fac, 'CUSTOM', c.p_start, c.p_end) b) $q$);
select pg_temp.run('1 Finance', 'monthly revenue trend adds up to gross', $q$
  select (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select coalesce(sum(t.gross_minor), 0)::text from seed_ctx c, get_revenue_trend(c.fac, 'CUSTOM', c.p_start, c.p_end, 'monthly') t) $q$);
select pg_temp.run('1 Finance', 'payment-method split adds up to gross', $q$
  select (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select coalesce(sum(m.amount_minor), 0)::text from seed_ctx c, get_payment_method_breakdown(c.fac, 'CUSTOM', c.p_start, c.p_end) m) $q$);
select pg_temp.run('1 Finance', 'ledger rows = payments + processed refunds + expenses', $q$
  select (select ((select count(*) from payments p, seed_ctx c where p.facility_id = c.fac and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to)
                + (select count(*) from refunds r, seed_ctx c where r.facility_id = c.fac and r.status = 'PROCESSED' and r.processed_at >= c.r_from and r.processed_at < c.r_to)
                + (select count(*) from expenses e, seed_ctx c where e.facility_id = c.fac and e.status = 'RECORDED' and e.spent_on between c.p_start and c.p_end))::text),
         (select l.total_count::text from seed_ctx c, list_finance_ledger(c.fac, 'CUSTOM', c.p_start, c.p_end, p_limit => 1) l limit 1) $q$);
select pg_temp.run('1 Finance', 'P&L: expenses and net follow the same totals', $q$
  select (select (s.gross_revenue_minor - s.refunds_minor - s.expenses_minor)::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select p.net_profit_minor::text from seed_ctx c, get_pnl(c.fac, 'CUSTOM', c.p_start, c.p_end) p) $q$);

-- ───────────────────────── 2. Finance: by sport (the top-bar selector) ─────────────────────────
-- a payment belongs to a sport through its source: court booking → the court's sport; membership → the batch its member is in;
-- coaching → the program's sport; guest in a released membership slot → the session's sport.
create function pg_temp.sport_gross(p_fs uuid) returns bigint language sql stable as $f$
  select (coalesce(sum(p.amount_inr), 0) * 100)::bigint from payments p, seed_ctx c
  where p.facility_id = c.fac and p.status = 'paid' and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to
    and (   exists (select 1 from bookings b join courts k on k.id = b.court_id where b.id = p.booking_id and k.facility_sport_id = p_fs)
         or exists (select 1 from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id where bm.membership_id = p.membership_id and mb.facility_sport_id = p_fs)
         or exists (select 1 from coaching_enrollments e join coaching_programs g on g.id = e.program_id where e.id = p.coaching_enrollment_id and g.facility_sport_id = p_fs)
         or exists (select 1 from membership_session_bookings sb join membership_sessions s on s.id = sb.session_id where sb.id = p.membership_session_booking_id and s.facility_sport_id = p_fs))
$f$;

select pg_temp.run('2 By sport', 'Cricket gross = payments sourced from cricket', $q$
  select pg_temp.sport_gross((select fs_crk from seed_ctx))::text,
         (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_crk]) s) $q$);
select pg_temp.run('2 By sport', 'Pickleball gross = payments sourced from pickleball', $q$
  select pg_temp.sport_gross((select fs_pkl from seed_ctx))::text,
         (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_pkl]) s) $q$);
select pg_temp.run('2 By sport', 'Badminton gross = payments sourced from badminton', $q$
  select pg_temp.sport_gross((select fs_bad from seed_ctx))::text,
         (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_bad]) s) $q$);
select pg_temp.run('2 By sport', 'two sports ticked = the two added together', $q$
  select (pg_temp.sport_gross((select fs_bad from seed_ctx)) + pg_temp.sport_gross((select fs_pkl from seed_ctx)))::text,
         (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_bad, c.fs_pkl]) s) $q$);
select pg_temp.run('2 By sport', 'sports + payments with no sport (older renewals, never-assigned members) = all sports', $q$
  select (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         ((pg_temp.sport_gross((select fs_bad from seed_ctx)) + pg_temp.sport_gross((select fs_pkl from seed_ctx)) + pg_temp.sport_gross((select fs_crk from seed_ctx))
           + (select (coalesce(sum(p.amount_inr), 0) * 100)::bigint from payments p, seed_ctx c
              where p.facility_id = c.fac and p.status = 'paid' and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to
                and not exists (select 1 from facility_sports fs where fs.facility_id = c.fac and payment_in_sports(p.id, array[fs.id]))))::text) $q$);
select pg_temp.run('2 By sport', 'refunds follow the sport of the booking they refund (Cricket)', $q$
  select (select coalesce(sum(r.amount_minor), 0)::bigint::text from refunds r, seed_ctx c
          where r.facility_id = c.fac and r.status = 'PROCESSED' and r.processed_at >= c.r_from and r.processed_at < c.r_to
            and exists (select 1 from bookings b join courts k on k.id = b.court_id where b.id = r.source_id and k.facility_sport_id = c.fs_crk)),
         (select s.refunds_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_crk]) s) $q$);
select pg_temp.run('2 By sport', 'expenses are NOT split by sport (Cricket selected = whole facility)', $q$
  select (select s.expenses_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select s.expenses_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_crk]) s) $q$);
select pg_temp.run('2 By sport', 'P&L under a sport: expenses stay facility-wide', $q$
  select (select p.total_expense_minor::text from seed_ctx c, get_pnl(c.fac, 'CUSTOM', c.p_start, c.p_end) p),
         (select p.total_expense_minor::text from seed_ctx c, get_pnl(c.fac, 'CUSTOM', c.p_start, c.p_end, null, array[c.fs_crk]) p) $q$);
select pg_temp.run('2 By sport', 'P&L under a sport: gross revenue narrows to the sport', $q$
  select pg_temp.sport_gross((select fs_crk from seed_ctx))::text,
         (select p.gross_revenue_minor::text from seed_ctx c, get_pnl(c.fac, 'CUSTOM', c.p_start, c.p_end, null, array[c.fs_crk]) p) $q$);
select pg_temp.run('2 By sport', 'ledger under a sport lists no expense rows', $q$
  select '0', (select count(*)::text from seed_ctx c, list_finance_ledger(c.fac, 'CUSTOM', c.p_start, c.p_end, 'EXPENSE', p_limit => 50, p_facility_sport_ids => array[c.fs_crk]) l) $q$);
select pg_temp.run('2 By sport', 'ledger under a sport = that sport''s payments + refunds', $q$
  select ((select count(*) from payments p, seed_ctx c
            where p.facility_id = c.fac and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to
              and (exists (select 1 from bookings b join courts k on k.id = b.court_id where b.id = p.booking_id and k.facility_sport_id = c.fs_crk)
                or exists (select 1 from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id where bm.membership_id = p.membership_id and mb.facility_sport_id = c.fs_crk)
                or exists (select 1 from coaching_enrollments e join coaching_programs g on g.id = e.program_id where e.id = p.coaching_enrollment_id and g.facility_sport_id = c.fs_crk)
                or exists (select 1 from membership_session_bookings sb join membership_sessions s on s.id = sb.session_id where sb.id = p.membership_session_booking_id and s.facility_sport_id = c.fs_crk)))
          + (select count(*) from refunds r, seed_ctx c
              where r.facility_id = c.fac and r.status = 'PROCESSED' and r.processed_at >= c.r_from and r.processed_at < c.r_to
                and exists (select 1 from bookings b join courts k on k.id = b.court_id where b.id = r.source_id and k.facility_sport_id = c.fs_crk)))::text,
         (select l.total_count::text from seed_ctx c, list_finance_ledger(c.fac, 'CUSTOM', c.p_start, c.p_end, p_limit => 1, p_facility_sport_ids => array[c.fs_crk]) l limit 1) $q$);
select pg_temp.run('2 By sport', 'pending payments under Cricket = cricket bookings + cricket members + cricket coaching still owed', $q$
  with c as (select * from seed_ctx), o as (
    select coalesce(b.amount_minor, 0)::bigint as tot,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'), 0)::bigint as paid
      from bookings b join courts k on k.id = b.court_id, c where b.facility_id = c.fac and b.status in ('pending', 'confirmed', 'completed') and k.facility_sport_id = c.fs_crk
    union all
    select (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.membership_id = ms.id and p.status = 'paid'), 0)::bigint
      from memberships ms, c where ms.facility_id = c.fac and ms.status <> 'cancelled'
        and exists (select 1 from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id where bm.membership_id = ms.id and mb.facility_sport_id = c.fs_crk)
    union all
    select coalesce(e.price_minor, 0)::bigint,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint
      from coaching_enrollments e join coaching_programs g on g.id = e.program_id, c where e.facility_id = c.fac and e.status <> 'CANCELLED' and g.facility_sport_id = c.fs_crk)
  select (select coalesce(sum(tot - paid), 0)::bigint::text from o where tot > 0 and paid < tot),
         (select s.outstanding_minor::text from seed_ctx c2, get_pending_payments_summary(c2.fac, null, null, array[c2.fs_crk]) s) $q$);

-- ───────────────────────── 3. Pending payments: due dates + ordering ─────────────────────────
select pg_temp.run('3 Pending', 'recurring coaching: next due date = the subscription''s current period end (never the start date)', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o
               join coaching_enrollment_billing b on b.enrollment_id = o.source_id
               where o.source_type = 'COACHING_ENROLLMENT' and b.kind = 'SUBSCRIPTION' and b.status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING')
                 and b.charge_count > 0 and b.current_end is not null and o.due_on <> b.current_end) $q$);
select pg_temp.run('3 Pending', 'recurring coaching cases exist in the list (so the check above means something)', $q$
  select 'true', ((select count(*) from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o
               join coaching_enrollment_billing b on b.enrollment_id = o.source_id
               where o.source_type = 'COACHING_ENROLLMENT' and b.status = 'ACTIVE' and b.charge_count > 0) > 0)::text $q$);
select pg_temp.run('3 Pending', 'AutoPay memberships: next due = subscription period end', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o
               join membership_subscriptions s on s.membership_id = o.source_id
               where o.source_type = 'MEMBERSHIP' and s.status::text in ('created', 'authenticated', 'active', 'pending')
                 and s.charge_count > 0 and s.current_end is not null and o.due_on <> s.current_end) $q$);
select pg_temp.run('3 Pending', 'a late-paying (halted/pending) subscription shows as OVERDUE', $q$
  select 'true', (exists (select 1 from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o
               join coaching_enrollment_billing b on b.enrollment_id = o.source_id
               where o.source_type = 'COACHING_ENROLLMENT' and b.status in ('PENDING', 'HALTED') and o.status = 'OVERDUE'))::text $q$);
select pg_temp.run('3 Pending', 'nothing is OVERDUE with a due date today or later', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o where o.status = 'OVERDUE' and o.due_on >= current_date) $q$);
select pg_temp.run('3 Pending', 'nothing past its due date is shown as merely PENDING', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o where o.status in ('PENDING', 'PARTIALLY_PAID') and o.due_on < current_date) $q$);
select pg_temp.run('3 Pending', 'oldest due date comes first (what the dashboard shows at the top)', $q$
  select (select min(o.due_on)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o),
         (select o.due_on::text from seed_ctx c, list_pending_payments(c.fac, p_sort => 'DUE_DATE', p_limit => 1) o) $q$);
select pg_temp.run('3 Pending', 'the dashboard''s "Today" list stops at today', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_to => current_date, p_limit => 100000) o where o.due_on > current_date) $q$);
select pg_temp.run('3 Pending', 'membership-included coaching (price 0) never appears as owing', $q$
  select '0', (select count(*)::text from seed_ctx c, list_pending_payments(c.fac, p_limit => 100000) o
               join coaching_enrollments e on e.id = o.source_id where e.pricing_type = 'MEMBERSHIP_INCLUDED') $q$);

-- ───────────────────────── 4. Reports ─────────────────────────
select pg_temp.run('4 Reports', 'bookings analytics total = bookings in the period', $q$
  select (select count(*)::text from bookings b, seed_ctx c where b.facility_id = c.fac and b.start_time >= c.r_from and b.start_time < c.r_to),
         (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) a) $q$);
select pg_temp.run('4 Reports', 'bookings: badminton + pickleball + cricket = all', $q$
  select (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) a),
         (select (b.total + p.total + k.total)::text from seed_ctx c,
                 get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_bad) b,
                 get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_pkl) p,
                 get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_crk) k) $q$);
select pg_temp.run('4 Reports', 'bookings: two sports ticked = the two added', $q$
  select (select (b.total + p.total)::text from seed_ctx c,
                 get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_bad) b,
                 get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_pkl) p),
         (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_bad, c.fs_pkl]) a) $q$);
select pg_temp.run('4 Reports', 'one sport via the old single argument = via the new list', $q$
  select (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, c.fs_crk) a),
         (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_crk]) a) $q$);
select pg_temp.run('4 Reports', 'cricket bookings = bookings on the turf', $q$
  select (select count(*)::text from bookings b join courts k on k.id = b.court_id, seed_ctx c
          where b.facility_id = c.fac and b.start_time >= c.r_from and b.start_time < c.r_to and k.facility_sport_id = c.fs_crk),
         (select a.total::text from seed_ctx c, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_crk]) a) $q$);
select pg_temp.run('4 Reports', 'utilisation is a sane percentage', $q$
  select 'true', (select (u.utilization_pct between 0 and 100)::text from seed_ctx c, get_overall_utilization(c.fac, 'CUSTOM', c.p_start, c.p_end) u) $q$);
select pg_temp.run('4 Reports', 'court utilisation lists all 5 courts (3 under Badminton)', $q$
  select '5|3', (select count(*)::text from seed_ctx c, get_court_utilization(c.fac, 'CUSTOM', c.p_start, c.p_end) u) || '|' ||
                (select count(*)::text from seed_ctx c, get_court_utilization(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_bad]) u) $q$);
select pg_temp.run('4 Reports', 'revenue by sport: the three sports plus (at most) one unlinked row, and the rows add up to gross revenue', $q$
  select (select s.gross_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select coalesce(sum(r.revenue_minor), 0)::text from seed_ctx c, get_revenue_by_sport(c.fac, 'CUSTOM', c.p_start, c.p_end) r) $q$);
select pg_temp.run('4 Reports', 'revenue by sport: no row is called Memberships; the only non-sport row is Not linked to a sport', $q$
  select '0', (select count(*)::text from seed_ctx c, get_revenue_by_sport(c.fac, 'CUSTOM', c.p_start, c.p_end) r
                where r.facility_sport_id is null and r.sport_name <> 'Not linked to a sport') $q$);
select pg_temp.run('4 Reports', 'revenue by sport: each sport row equals that sport''s own payments (Cricket)', $q$
  select pg_temp.sport_gross((select fs_crk from seed_ctx))::text,
         (select r.revenue_minor::text from seed_ctx c, get_revenue_by_sport(c.fac, 'CUSTOM', c.p_start, c.p_end) r where r.facility_sport_id = c.fs_crk) $q$);
select pg_temp.run('4 Reports', 'memberships report: active members = active memberships', $q$
  select (select count(*)::text from memberships m, seed_ctx c where m.facility_id = c.fac and m.status = 'active'),
         (select a.active_members::text from seed_ctx c, get_membership_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) a) $q$);
select pg_temp.run('4 Reports', 'memberships report under Cricket = active cricket-batch members', $q$
  select (select count(*)::text from memberships m, seed_ctx c where m.facility_id = c.fac and m.status = 'active'
            and exists (select 1 from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id where bm.membership_id = m.id and mb.facility_sport_id = c.fs_crk)),
         (select a.active_members::text from seed_ctx c, get_membership_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, array[c.fs_crk]) a) $q$);
select pg_temp.run('4 Reports', 'memberships report revenue = membership payments', $q$
  select (select (coalesce(sum(p.amount_inr), 0) * 100)::bigint::text from payments p, seed_ctx c
          where p.facility_id = c.fac and p.status = 'paid' and p.membership_id is not null and coalesce(p.paid_at, p.created_at) >= c.r_from and coalesce(p.paid_at, p.created_at) < c.r_to),
         (select a.membership_revenue_minor::text from seed_ctx c, get_membership_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) a) $q$);
select pg_temp.run('4 Reports', 'guest-booking report runs for all sports and for one', $q$
  select 'ok|ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_guest_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) g) || '|' ||
                  (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_guest_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_bad]) g) $q$);
select pg_temp.run('4 Reports', 'overview report: revenue and booking totals match the other reports', $q$
  select (select s.gross_revenue_minor::text || '|' || a.total::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s, get_booking_analytics(c.fac, 'CUSTOM', c.p_start, c.p_end) a),
         (select o.gross_revenue_minor::text || '|' || o.total_bookings::text from seed_ctx c, get_analytics_overview(c.fac, 'CUSTOM', c.p_start, c.p_end) o) $q$);

-- Memberships report: Total / Active / Inactive members as of the end of the dates (migration 0143).
select pg_temp.run('4 Reports', 'member counts follow the dates: people registered or running in them; active = not ended or cancelled', $q$
  select (select (select count(distinct m.member_id) from memberships m
                   where m.facility_id = c.fac and (((m.created_at at time zone c.tz)::date between c.p_start and current_date)
                                                   or (m.start_date <= current_date and m.end_date >= c.p_start)))::text || '|' ||
                 (select count(distinct m.member_id) from memberships m
                   where m.facility_id = c.fac and (((m.created_at at time zone c.tz)::date between c.p_start and current_date)
                                                   or (m.start_date <= current_date and m.end_date >= c.p_start))
                     and m.status <> 'cancelled' and m.end_date >= current_date)::text from seed_ctx c),
         (select n.total_members::text || '|' || n.active_members::text from seed_ctx c, get_membership_member_counts(c.fac, c.p_start, current_date) n) $q$);
select pg_temp.run('4 Reports', 'everyone registered this month is counted, even if their membership starts later', $q$
  select 'true', (select (n.total_members >= (select count(distinct m.member_id) from memberships m
                                              where m.facility_id = c.fac
                                                and (m.created_at at time zone c.tz)::date between date_trunc('month', current_date)::date
                                                                                                and (date_trunc('month', current_date) + interval '1 month - 1 day')::date))::text
                    from seed_ctx c, get_membership_member_counts(c.fac, date_trunc('month', current_date)::date,
                                                                  (date_trunc('month', current_date) + interval '1 month - 1 day')::date) n) $q$);
select pg_temp.run('4 Reports', 'a short past window shows fewer total members than the whole history, and inactive = total - active', $q$
  select 'true', (select ((n.inactive_members = n.total_members - n.active_members)
                          and (select o.total_members from get_membership_member_counts(c.fac, c.p_start + 400, c.p_start + 430) o) <= n.total_members)::text
                    from seed_ctx c, get_membership_member_counts(c.fac, c.p_start, current_date) n) $q$);

-- Memberships by sport / court / timing (migration 0147).
select pg_temp.run('4 Reports', 'timings: no batch has more members than the report''s Total Members, and sport totals cover their courts', $q$
  select '0', (select count(*)::text from seed_ctx c, get_membership_batch_breakdown(c.fac, c.p_start, current_date) b,
                      get_membership_member_counts(c.fac, c.p_start, current_date) n
                where b.batch_id is not null and (b.members > n.total_members or b.court_members > b.sport_members or b.members > b.court_members)) $q$);
select pg_temp.run('4 Reports', 'timings: the four live batches and the ended one all appear for the whole history, plus the unassigned row', $q$
  select 'true', (select ((select count(*) from get_membership_batch_breakdown(c.fac, c.p_start, current_date) b where b.batch_id is not null) = 5
                          and exists (select 1 from get_membership_batch_breakdown(c.fac, c.p_start, current_date) b where b.batch_id is null and b.members > 0))::text from seed_ctx c) $q$);

-- Court Utilization counts guest bookings + membership batch time + coaching sessions (migration 0142), merged per court.
select pg_temp.run('4 Reports', 'Badminton Court 1: the Mon-Sat 6am membership batch alone is 6 h in a full past week', $q$
  select 'true', (select (u.booked_minutes >= 360)::text
                    from seed_ctx c, get_court_utilization(c.fac, 'CUSTOM', date_trunc('week', current_date - 14)::date, (date_trunc('week', current_date - 14)::date) + 6) u
                   where u.court_name = 'Badminton Court 1') $q$);
select pg_temp.run('4 Reports', 'Cricket Turf: weekend membership nets (4 h) + Sunday coaching (2 h) are counted', $q$
  select 'true', (select (u.booked_minutes >= 360)::text
                    from seed_ctx c, get_court_utilization(c.fac, 'CUSTOM', date_trunc('week', current_date - 14)::date, (date_trunc('week', current_date - 14)::date) + 6) u
                   where u.court_name = 'Cricket Turf') $q$);
select pg_temp.run('4 Reports', 'no court is ever shown as booked for more than its open hours (overlaps count once)', $q$
  select '0', (select count(*)::text from seed_ctx c, get_court_utilization(c.fac, 'CUSTOM', c.p_start, c.p_end) u where u.booked_minutes > u.open_minutes) $q$);
select pg_temp.run('4 Reports', 'coaching time shows up in the peak-hours and heatmap too (Sunday 4 pm on the turf)', $q$
  select 'true', (select (coalesce(sum(h.booked_minutes), 0) > 0)::text
                    from seed_ctx c, get_demand_heatmap(c.fac, 'CUSTOM', c.p_start, c.p_end, p_facility_sport_ids => array[c.fs_crk]) h
                   where h.dow = 0 and h.hour = 16) $q$);

-- ───────────────────────── 5. Coaching ─────────────────────────
select pg_temp.run('5 Coaching', 'coaching revenue (all) = coaching payments', $q$
  select (select (coalesce(sum(p.amount_inr), 0) * 100)::bigint::text from payments p, seed_ctx c where p.facility_id = c.fac and p.status = 'paid' and p.coaching_enrollment_id is not null),
         (select get_coaching_total_revenue(c.fac)::text from seed_ctx c) $q$);
select pg_temp.run('5 Coaching', 'coaching revenue under Cricket = the Cricket academy''s payments', $q$
  select (select (coalesce(sum(p.amount_inr), 0) * 100)::bigint::text from payments p join coaching_enrollments e on e.id = p.coaching_enrollment_id
            join coaching_programs g on g.id = e.program_id, seed_ctx c where p.facility_id = c.fac and p.status = 'paid' and g.facility_sport_id = c.fs_crk),
         (select get_coaching_total_revenue(c.fac, array[c.fs_crk])::text from seed_ctx c) $q$);
select pg_temp.run('5 Coaching', 'students (all) = distinct students enrolled', $q$
  select (select count(distinct e.member_id)::text from coaching_enrollments e, seed_ctx c where e.facility_id = c.fac),
         (select (get_student_card_stats(c.fac) ->> 'totalStudents') from seed_ctx c) $q$);
select pg_temp.run('5 Coaching', 'students under Pickleball = students of the pickleball program', $q$
  select (select count(distinct e.member_id)::text from coaching_enrollments e join coaching_programs g on g.id = e.program_id, seed_ctx c where e.facility_id = c.fac and g.facility_sport_id = c.fs_pkl),
         (select (get_student_card_stats(c.fac, array[c.fs_pkl]) ->> 'totalStudents') from seed_ctx c) $q$);
select pg_temp.run('5 Coaching', 'past sessions exist and today onward are generated by the app', $q$
  select 'true', ((select count(*) from coaching_sessions s, seed_ctx c where s.facility_id = c.fac and s.status = 'COMPLETED') > 100
                 and (select count(*) from coaching_sessions s, seed_ctx c where s.facility_id = c.fac and s.status in ('SCHEDULED', 'CONFIRMED') and s.start_at > now()) > 0)::text $q$);

-- ───────────────────────── 6. Daily closing ─────────────────────────
select pg_temp.run('6 Daily closing', 'a closed day''s live figures = what was closed', $q$
  with d as (select * from daily_closings x, seed_ctx c where x.facility_id = c.fac and x.status = 'CLOSED' order by x.closing_date desc limit 1)
  select (select (d.cash_collected_minor::text || '|' || d.expected_cash_minor::text) from d),
         (select (s.cash_collected_minor::text || '|' || s.expected_cash_minor::text) from d, get_daily_closing_summary(d.fac, d.closing_date) s) $q$);
select pg_temp.run('6 Daily closing', 'expenses page figure: pending expenses = unpaid + part-paid balance', $q$
  select (select coalesce(sum(e.amount_minor - e.amount_paid_minor), 0)::bigint::text from expenses e, seed_ctx c where e.facility_id = c.fac and e.status = 'RECORDED' and e.payment_status in ('PENDING', 'PARTIAL')),
         (select s.pending_minor::text from seed_ctx c, get_expense_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s) $q$);

-- ───────────────────────── 7. Backward compatibility: the OLD call shapes still work ─────────────────────────
select pg_temp.run('7 Compat', 'get_finance_summary(facility, preset) — 2 arguments', $q$ select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_finance_summary(c.fac, 'THIS_MONTH') s) $q$);
select pg_temp.run('7 Compat', 'get_pending_payments_summary(facility) — 1 argument', $q$ select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_pending_payments_summary(c.fac) s) $q$);
select pg_temp.run('7 Compat', 'get_booking_analytics — the old 6 positional arguments', $q$
  select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_booking_analytics(c.fac, 'THIS_MONTH', null::date, null::date, null::uuid, null::uuid) a) $q$);
select pg_temp.run('7 Compat', 'get_booking_analytics — old single-sport argument by name', $q$
  select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_booking_analytics(p_facility_id => c.fac, p_preset => 'THIS_MONTH', p_facility_sport_id => c.fs_bad) a) $q$);
select pg_temp.run('7 Compat', 'get_membership_analytics(facility, preset)', $q$ select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_membership_analytics(c.fac, 'THIS_MONTH') a) $q$);
select pg_temp.run('7 Compat', 'get_memberships_by_type(facility, preset)', $q$ select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_memberships_by_type(c.fac, 'THIS_MONTH') a) $q$);
select pg_temp.run('7 Compat', 'list_finance_ledger — 11 positional arguments', $q$
  select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, list_finance_ledger(c.fac, 'THIS_MONTH', null::date, null::date, null::text, null::text, null::text, null::text, null::text, 10, 0) l) $q$);
select pg_temp.run('7 Compat', 'get_revenue_trend / breakdown / payment methods with the old arguments', $q$
  select 'ok', case when (select count(*) from seed_ctx c, get_revenue_trend(c.fac, 'THIS_MONTH', null, null, 'daily') t) >= 0
                     and (select count(*) from seed_ctx c, get_revenue_breakdown(c.fac, 'THIS_MONTH') b) >= 0
                     and (select count(*) from seed_ctx c, get_payment_method_breakdown(c.fac, 'THIS_MONTH') m) >= 0 then 'ok' end $q$);
select pg_temp.run('7 Compat', 'get_pnl / get_pnl_trend with the old arguments', $q$
  select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_pnl(c.fac, 'THIS_MONTH') p) $q$);
select pg_temp.run('7 Compat', 'list_pending_payments with the old 10 arguments (Flutter / record page)', $q$
  select 'ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, list_pending_payments(c.fac, null, null, 'ALL_OUTSTANDING', null::date, null::date, 'DUE_DATE', 20, 0, null::uuid) o) $q$);
select pg_temp.run('7 Compat', 'sessions + coaching functions called the old way (no sports argument)', $q$
  select 'ok|ok', (select case when count(*) >= 0 then 'ok' end from seed_ctx c, get_membership_sessions_summary(c.fac) s) || '|' ||
                  (select case when get_coaching_overview(c.fac) is not null then 'ok' end from seed_ctx c) $q$);

-- ───────────────────────── 8. Reports & Analytics overview cards (migration 0140) ─────────────────────────
select pg_temp.run('8 Overview', 'Total Revenue = payments less refunds, same as Finance', $q$
  select (select (s.gross_revenue_minor - s.refunds_minor)::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'totalRevenueMinor') from seed_ctx c) $q$);
select pg_temp.run('8 Overview', 'Total Expenses and Net Revenue agree with Finance', $q$
  select (select s.expenses_minor::text || '|' || s.net_revenue_minor::text from seed_ctx c, get_finance_summary(c.fac, 'CUSTOM', c.p_start, c.p_end) s),
         (select (o ->> 'totalExpensesMinor') || '|' || (o ->> 'netRevenueMinor') from seed_ctx c, get_reports_overview(c.fac, c.p_start, c.p_end) o) $q$);
select pg_temp.run('8 Overview', 'Guest Booking count = guest bookings in the dates (all statuses)', $q$
  select (select count(*)::text from bookings b, seed_ctx c where b.facility_id = c.fac and b.customer_type = 'GUEST' and b.start_time >= c.r_from and b.start_time < c.r_to),
         (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'guestBookings') from seed_ctx c) $q$);
select pg_temp.run('8 Overview', 'Total Members / Program / Coach / Students follow the dates', $q$
  select (select (select count(distinct m.member_id) from memberships m where m.facility_id = c.fac and m.status <> 'cancelled' and m.start_date <= c.p_end and m.end_date >= c.p_start)::text || '|' ||
                 (select count(*) from coaching_programs p where p.facility_id = c.fac and p.status in ('ACTIVE', 'COMPLETED', 'PAUSED')
                    and coalesce(p.start_date, p.created_at::date) <= c.p_end and coalesce(p.end_date, c.p_end) >= c.p_start)::text || '|' ||
                 (select count(*) from coaches k where k.facility_id = c.fac and k.status in ('ACTIVE', 'ON_LEAVE') and coalesce(k.joined_on, k.created_at::date) <= c.p_end)::text || '|' ||
                 (select count(distinct e.member_id) from coaching_enrollments e where e.facility_id = c.fac and e.start_date <= c.p_end
                    and coalesce(e.cancelled_at::date, e.end_date, c.p_end) >= c.p_start)::text from seed_ctx c),
         (select (o ->> 'members') || '|' || (o ->> 'programs') || '|' || (o ->> 'coaches') || '|' || (o ->> 'students')
            from seed_ctx c, get_reports_overview(c.fac, c.p_start, c.p_end) o) $q$);
select pg_temp.run('8 Overview', 'a quiet past month shows fewer members than the whole history', $q$
  select 'true', (select ((get_reports_overview(c.fac, c.p_start, c.p_start + 6) ->> 'members')::int
                          <= (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'members')::int)::text from seed_ctx c) $q$);
select pg_temp.run('8 Overview', 'Guest / Membership / Coaching revenue = the Finance revenue breakdown', $q$
  select (select b.guest_booking_revenue_minor::text || '|' || b.membership_revenue_minor::text || '|' || b.coaching_revenue_minor::text
            from seed_ctx c, get_revenue_breakdown(c.fac, 'CUSTOM', c.p_start, c.p_end) b),
         (select (o ->> 'guestBookingRevenueMinor') || '|' || (o ->> 'membershipRevenueMinor') || '|' || (o ->> 'coachingRevenueMinor')
            from seed_ctx c, get_reports_overview(c.fac, c.p_start, c.p_end) o) $q$);
select pg_temp.run('8 Overview', 'Coaching Expenses = recorded expenses filed under Coaching', $q$
  select (select coalesce(sum(e.amount_minor), 0)::bigint::text from expenses e join expense_categories k on k.id = e.category_id, seed_ctx c
          where e.facility_id = c.fac and e.status = 'RECORDED' and e.spent_on between c.p_start and c.p_end and lower(k.name) = 'coaching'),
         (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'coachingExpensesMinor') from seed_ctx c) $q$);
select pg_temp.run('8 Overview', 'under Cricket the sport-scoped cards narrow; expenses stay facility-wide', $q$
  select (select pg_temp.sport_gross(c.fs_crk)::text from seed_ctx c) || '|' || (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'totalExpensesMinor') from seed_ctx c),
         (select ((o ->> 'guestBookingRevenueMinor')::bigint + (o ->> 'membershipRevenueMinor')::bigint + (o ->> 'coachingRevenueMinor')::bigint
                  + (select coalesce(sum(v.amount_minor), 0) from finance_transactions_view v where v.facility_id = c.fac and v.status = 'paid'
                       and v.effective_at >= c.r_from and v.effective_at < c.r_to and v.source_type = 'MEMBER_BOOKING' and payment_in_sports(v.id, array[c.fs_crk])))::text
                 || '|' || (o ->> 'totalExpensesMinor')
            from seed_ctx c, get_reports_overview(c.fac, c.p_start, c.p_end, array[c.fs_crk]) o) $q$);
select pg_temp.run('8 Overview', 'chart of Total Revenue adds up to the card', $q$
  select (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'totalRevenueMinor') from seed_ctx c),
         (select coalesce(sum(t.value), 0)::text from seed_ctx c, get_reports_overview_trend(c.fac, 'REVENUE', c.p_start, c.p_end, 'monthly') t) $q$);
select pg_temp.run('8 Overview', 'chart of Net Revenue adds up to the card', $q$
  select (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'netRevenueMinor') from seed_ctx c),
         (select coalesce(sum(t.value), 0)::text from seed_ctx c, get_reports_overview_trend(c.fac, 'NET', c.p_start, c.p_end, 'monthly') t) $q$);
select pg_temp.run('8 Overview', 'chart of Guest Bookings adds up to the card', $q$
  select (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'guestBookings') from seed_ctx c),
         (select coalesce(sum(t.value), 0)::text from seed_ctx c, get_reports_overview_trend(c.fac, 'GUEST_BOOKINGS', c.p_start, c.p_end, 'weekly') t) $q$);
select pg_temp.run('8 Overview', 'chart of Expenses adds up to the card (day, week and month agree)', $q$
  select (select (get_reports_overview(c.fac, c.p_start, c.p_end) ->> 'totalExpensesMinor') from seed_ctx c),
         (select (select coalesce(sum(t.value), 0) from get_reports_overview_trend(c.fac, 'EXPENSES', c.p_start, c.p_end, 'daily') t)::text
                 || '' from seed_ctx c) $q$);
select pg_temp.run('8 Overview', 'every card has a chart (all twelve metrics answer)', $q$
  select '12', (select count(*)::text from seed_ctx c, unnest(array['REVENUE','EXPENSES','NET','GUEST_BOOKINGS','MEMBERS','PROGRAMS','COACHES','STUDENTS',
                'GUEST_BOOKING_REVENUE','MEMBERSHIP_REVENUE','COACHING_REVENUE','COACHING_EXPENSES']) m
                where (select count(*) from get_reports_overview_trend(c.fac, m, c.p_start, c.p_end, 'monthly')) >= 0) $q$);

-- ───────────────────────── result ─────────────────────────
select 0 as n, 'SUMMARY' as area, (count(*) filter (where ok))::text || ' passed, ' || (count(*) filter (where not ok))::text || ' FAILED of ' || count(*)::text as test,
       '' as expected, '' as actual, bool_and(ok) as ok
from seed_checks
union all
select n, area, test, expected, actual, ok from seed_checks
order by ok nulls first, n;

rollback;

-- ═══════════════════════════════════════════════════════════════════════════
-- THEN CHECK BY EYE (web + Flutter) — what the automatic checks cannot see
--
--  Guest Booking      Calendar for a busy Saturday shows bookings on all 5 courts; a booking made today for a
--                     slot already held by a membership batch / coaching batch is refused; Guest Players lists
--                     ~60 guests with several repeat visitors; an unpaid played booking shows "Pending" and
--                     appears in Pending Payments as OVERDUE.
--  Membership         Dashboard: Total Members ~90, Overall Revenue = all membership payments ever, Payment
--                     Pending = unpaid balances + lapsed renewals (not double counted). Members who left show
--                     as inactive; the newest joined in the last weeks. AutoPay members show a next charge date.
--                     Membership Sessions: batches B1–B4 active, B5 ended; released slots show guest bookings.
--  Coaching           Students: ~65 across Badminton/Cricket/Pickleball; cancelled + completed ones present;
--                     a monthly student who paid month 1 shows "next due" next month, not the start date;
--                     late payers (halted) show overdue. Schedule shows future sessions generated by the app.
--  Finance            Dashboard over "This Year" and "All"; tick Badminton only, then Cricket only — gross,
--                     refunds, payment methods, trend, recent transactions all change; expenses and net show the
--                     "not split by sport" note. Expenses + Daily Closing lock the selector to All Sports.
--                     Daily Closing: last 60 days closed (a few missing days, a couple reopened), today open.
--  Reports            Open each of the 6 reports; change the top-bar sport and the figures follow; compare the
--                     Revenue report total with the Finance dashboard for the same period (must match).
--  Pending / Attention  Home → Attention Required lists overdue first (longest overdue at the very top) with a
--                     total and an overdue total; "Today" shows only what is overdue or due by today.
--  Mobile             Same Home card ("Needs You"), Pending Payments, Members summary card, Coaching.
-- ═══════════════════════════════════════════════════════════════════════════
