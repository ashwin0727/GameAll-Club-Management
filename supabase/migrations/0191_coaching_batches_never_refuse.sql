-- ═══════════════════════════════════════════════════════════════════════════
-- A coaching batch never refuses a student because it is "full".
--
-- Capacity stays a guide: the screens show enrolled / capacity, and once more students than the capacity have joined they show
-- 11/11 (the capacity follows the count). A batch stops taking students only when the club closes the programme or the batch
-- (status, deadline, end date), which the enrolment functions already check.
--
-- Both enrolment routines (the Player app's and the club's) had a "This batch is full." check. The check is switched off in place.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  f record;
  v_def text;
  v_new text;
  v_done integer := 0;
begin
  for f in
    select p.oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosrc like '%This batch is full.%'
  loop
    v_def := pg_get_functiondef(f.oid);
    v_new := replace(v_def, 'raise exception ''This batch is full.'' using errcode = ''23514'';', 'null;');
    if v_new <> v_def then
      execute v_new;
      v_done := v_done + 1;
    end if;
  end loop;
  if v_done = 0 then
    raise exception 'No batch-full check was found to switch off.';
  end if;
end $$;

notify pgrst, 'reload schema';
