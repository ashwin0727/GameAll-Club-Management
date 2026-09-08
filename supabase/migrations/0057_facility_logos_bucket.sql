-- ═══════════════════════════════════════════════════════════════════════════
-- Facility logo uploads (onboarding redesign — Screen 1)
--
-- Public bucket: logos appear on the public booking page and on invoices,
-- so reads are open. Writes are scoped to a folder named after the
-- uploader's user id, since the facility row does not exist yet when the
-- owner picks a logo on the Facility Details step.
-- ═══════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('facility-logos', 'facility-logos', true)
on conflict (id) do nothing;

create policy "facility logos are publicly readable"
  on storage.objects for select
  using (bucket_id = 'facility-logos');

create policy "owners upload their own facility logo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'facility-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "owners replace their own facility logo"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'facility-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
