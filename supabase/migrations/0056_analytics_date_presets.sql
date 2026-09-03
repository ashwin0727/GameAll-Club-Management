-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 1.
--
-- Analytics reuses Finance's date-range resolver so "This Month" means the
-- same window in both places, forever. The Reports brief adds two presets
-- Finance never needed: This Quarter and This Year.
--
-- This is `create or replace` of resolve_finance_date_range with the same
-- signature and every existing branch byte-identical — only two new
-- `elsif` arms. No Finance RPC or UI changes; the Finance date picker
-- simply doesn't offer the new presets.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function resolve_finance_date_range(
  p_facility_id uuid,
  p_preset text,
  p_start_date date default null,
  p_end_date date default null
) returns tstzrange
language plpgsql
stable
as $$
declare
  tz text;
  today date;
  range_start date;
  range_end_exclusive date;
begin
  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');
  today := (now() at time zone tz)::date;

  if p_preset = 'TODAY' then
    range_start := today; range_end_exclusive := today + 1;
  elsif p_preset = 'YESTERDAY' then
    range_start := today - 1; range_end_exclusive := today;
  elsif p_preset = 'THIS_WEEK' then
    range_start := date_trunc('week', today)::date; range_end_exclusive := range_start + 7;
  elsif p_preset = 'LAST_WEEK' then
    range_start := date_trunc('week', today)::date - 7; range_end_exclusive := range_start + 7;
  elsif p_preset = 'THIS_MONTH' then
    range_start := date_trunc('month', today)::date; range_end_exclusive := (date_trunc('month', today) + interval '1 month')::date;
  elsif p_preset = 'LAST_MONTH' then
    range_start := (date_trunc('month', today) - interval '1 month')::date; range_end_exclusive := date_trunc('month', today)::date;
  elsif p_preset = 'THIS_QUARTER' then
    range_start := date_trunc('quarter', today)::date; range_end_exclusive := (date_trunc('quarter', today) + interval '3 months')::date;
  elsif p_preset = 'THIS_YEAR' then
    range_start := date_trunc('year', today)::date; range_end_exclusive := (date_trunc('year', today) + interval '1 year')::date;
  elsif p_preset = 'CUSTOM' then
    if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
      raise exception 'A custom date range requires a valid start and end date.' using errcode = '22023';
    end if;
    range_start := p_start_date; range_end_exclusive := p_end_date + 1;
  else
    raise exception 'Unknown date range preset: %', p_preset using errcode = '22023';
  end if;

  return tstzrange(range_start::timestamp at time zone tz, range_end_exclusive::timestamp at time zone tz, '[)');
end;
$$;

grant execute on function resolve_finance_date_range(uuid, text, date, date) to authenticated;
