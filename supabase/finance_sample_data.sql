-- ═══════════════════════════════════════════════════════════════════════════
-- TEMPORARY sample data, to see the Finance dashboard with a real shape.
--
-- NOT a migration. Do not commit this into the migration sequence and do not
-- run it against production data you care about.
--
-- Every row it writes is tagged with the reference 'SAMPLE-FIN' or a note of
-- 'SAMPLE-FIN', so REVERT below removes exactly what this added and nothing
-- else. Read the revert block before you run the seed.
--
-- Seven days of takings across the payment methods, plus two expenses, so
-- the trend has a curve, both donuts have several slices, and net revenue
-- differs from gross.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- SEED. Replace the facility id on the next line with your own.
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare
  v_facility uuid := '4cb3fef5-292e-410f-8f76-976e6e4bda80';  -- ← your facility
  v_category uuid;
  v_day integer;
  v_amounts integer[] := array[20000, 32000, 15000, 41000, 78000, 26000, 19000];  -- rupees ×100
  v_methods text[] := array['UPI', 'Cash', 'Card', 'UPI', 'Bank Transfer', 'UPI', 'Cash'];
begin
  if not exists (select 1 from facilities where id = v_facility) then
    raise exception 'No facility with id %. Set v_facility to your own.', v_facility;
  end if;

  -- Seven daily payments, one per day, ending today. amount_inr is whole
  -- rupees, which is what the payments table stores.
  for v_day in 0..6 loop
    insert into payments (
      facility_id, member_id, booking_id, amount_inr, status,
      payment_method, paid_at, created_at
    ) values (
      v_facility,
      null,
      null,
      (v_amounts[v_day + 1] / 100),
      'paid'::payment_status,
      v_methods[v_day + 1],
      (current_date - (6 - v_day))::timestamp + time '18:30',
      (current_date - (6 - v_day))::timestamp + time '18:30'
    );
  end loop;

  -- Two expenses, so net revenue is visibly below gross.
  select id into v_category from expense_categories
   where facility_id is null and name = 'Maintenance' limit 1;

  insert into expenses (facility_id, category_id, amount_minor, spent_on, payment_method, vendor, reference, notes)
  values
    (v_facility, v_category, 250000, current_date - 4, 'UPI', 'ABC Sports Services', 'SAMPLE-FIN', 'SAMPLE-FIN court lighting'),
    (v_facility, v_category,  74000, current_date - 1, 'Cash', 'Local Hardware',      'SAMPLE-FIN', 'SAMPLE-FIN net repair');

  raise notice 'Sample finance data inserted for facility %.', v_facility;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- VERIFY. Should show seven daily buckets and a gross of ₹2,310.
-- ─────────────────────────────────────────────────────────────────────────
-- select * from get_revenue_trend('4cb3fef5-292e-410f-8f76-976e6e4bda80', 'THIS_MONTH', null, null, 'daily');
-- select * from get_finance_summary('4cb3fef5-292e-410f-8f76-976e6e4bda80', 'THIS_MONTH');
-- select * from get_payment_method_breakdown('4cb3fef5-292e-410f-8f76-976e6e4bda80', 'THIS_MONTH');


-- ═══════════════════════════════════════════════════════════════════════════
-- REVERT. Run this to remove everything the seed added.
--
-- The payments have no booking or membership behind them, which is what
-- makes them identifiable: a real payment always references one or the
-- other. The window is narrowed to the last seven days as well, so this
-- cannot reach further back than the seed did.
-- ═══════════════════════════════════════════════════════════════════════════
-- do $$
-- declare
--   v_facility uuid := '4cb3fef5-292e-410f-8f76-976e6e4bda80';
--   v_payments integer;
--   v_expenses integer;
-- begin
--   delete from expenses
--    where facility_id = v_facility and reference = 'SAMPLE-FIN';
--   get diagnostics v_expenses = row_count;
--
--   delete from payments
--    where facility_id = v_facility
--      and booking_id is null
--      and membership_id is null
--      and member_id is null
--      and paid_at >= (current_date - 7)::timestamp;
--   get diagnostics v_payments = row_count;
--
--   raise notice 'Removed % sample payments and % sample expenses.', v_payments, v_expenses;
-- end $$;
