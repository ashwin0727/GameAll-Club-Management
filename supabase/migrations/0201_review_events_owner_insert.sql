-- Fix for 0200: complete_facility_setup (security invoker) writes a SUBMITTED row to facility_review_events as the signed-in owner,
-- but the table had row-level security on and no policy, so finishing setup failed with 42501.
--
-- An owner may add ONLY their own SUBMITTED / RESUBMITTED rows for their own facility. Approvals and rejections are written by
-- admin_review_facility_setup (security definer) and nobody can read the table directly.
drop policy if exists "review_events_owner_submit" on facility_review_events;
create policy "review_events_owner_submit" on facility_review_events for insert
  with check (
    action in ('SUBMITTED', 'RESUBMITTED')
    and actor = auth.uid()
    and has_facility_role(facility_id, array['owner']::facility_role[])
  );
