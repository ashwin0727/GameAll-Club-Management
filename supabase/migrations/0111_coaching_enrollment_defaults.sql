-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching enrollments — fill in the end date and coach automatically.
--
-- Add Student never sends an end date or a coach, so every enrollment was
-- stored with both empty and the enrollment page showed "—" for End date and
-- Coach. Both are already decided elsewhere:
--
--   end_date  ← the program's end_date (the date the program finishes)
--   coach_id  ← the selected batch's coach (a batch is one day/time/court/coach)
--
-- A BEFORE INSERT trigger applies them only when the caller left them empty,
-- so an explicit value always wins and create_coaching_enrollment's signature
-- is untouched. The program end date is only used when it is not before the
-- enrollment start (an enrollment may not end before it starts — the table's
-- date check would reject it). Existing enrollments are backfilled once.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function coaching_enrollment_apply_defaults()
returns trigger
language plpgsql
as $$
declare
  v_program_end date;
  v_batch_coach uuid;
begin
  if new.end_date is null then
    select end_date into v_program_end from coaching_programs where id = new.program_id;
    if v_program_end is not null and v_program_end >= new.start_date then
      new.end_date := v_program_end;
    end if;
  end if;

  if new.coach_id is null and new.batch_id is not null then
    select coach_id into v_batch_coach from coaching_program_batches where id = new.batch_id;
    new.coach_id := v_batch_coach;
  end if;

  return new;
end;
$$;

drop trigger if exists coaching_enrollments_apply_defaults on coaching_enrollments;
create trigger coaching_enrollments_apply_defaults
  before insert on coaching_enrollments
  for each row execute function coaching_enrollment_apply_defaults();


-- ─────────────────────────────────────────────────────────────────────────
-- One-time backfill for enrollments created before this migration. Only
-- empty values are filled — nothing a user set is overwritten.
-- ─────────────────────────────────────────────────────────────────────────
-- Start date: Add Student used to default the start to today even for a program
-- that begins later. Correct only the rows where the start is exactly the day the
-- enrollment was created (i.e. the untouched default) and the program starts after
-- it. Monthly enrollments with online billing are skipped — their cycle count was
-- derived from the start date and must not shift under a live mandate.
update coaching_enrollments e
   set start_date = p.start_date
  from coaching_programs p
 where p.id = e.program_id
   and p.start_date is not null
   and p.start_date > e.start_date
   and e.start_date = (e.created_at at time zone 'Asia/Kolkata')::date
   and (e.end_date is null or e.end_date >= p.start_date)
   and not (e.fee_type = 'MONTHLY' and exists (select 1 from coaching_enrollment_billing b where b.enrollment_id = e.id));

update coaching_enrollments e
   set end_date = p.end_date
  from coaching_programs p
 where p.id = e.program_id
   and e.end_date is null
   and p.end_date is not null
   and p.end_date >= e.start_date;

update coaching_enrollments e
   set coach_id = b.coach_id
  from coaching_program_batches b
 where b.id = e.batch_id
   and e.coach_id is null
   and b.coach_id is not null;
