-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching page cards: Total Coaches (all statuses) and Coaching Expense (this month).
--
-- Coaching expenses are recorded on the Expenses page like any other expense, under a "Coaching"
-- category — this adds that shared default category and sums the month's recorded expenses in it.
-- Voided expenses are ignored. The month follows the facility's own timezone.
-- ═══════════════════════════════════════════════════════════════════════════

insert into expense_categories (facility_id, name, sort_order)
values (null, 'Coaching', 35)
on conflict do nothing;

create or replace function get_coaching_card_stats(p_facility_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  month_start date;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  month_start := date_trunc('month', now() at time zone tz)::date;

  return jsonb_build_object(
    'totalCoaches', (select count(*) from coaches where facility_id = p_facility_id),
    'coachingExpenseMinor', (
      select coalesce(sum(x.amount_minor), 0)::bigint
      from expenses x
      join expense_categories c on c.id = x.category_id
      where x.facility_id = p_facility_id
        and x.status = 'RECORDED'
        and lower(c.name) = 'coaching'
        and x.spent_on >= month_start
        and x.spent_on < (month_start + interval '1 month')::date
    )
  );
end;
$$;

grant execute on function get_coaching_card_stats(uuid) to authenticated;
