-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching program image uploads — same shape as facility-logos (0057) and
-- avatars (0096): a public bucket, reads open (the image is shown on the
-- program card/preview everywhere), writes scoped to a folder named after the
-- uploader's own user id.
-- ═══════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('program-images', 'program-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "program images are publicly readable" on storage.objects;
create policy "program images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'program-images');

drop policy if exists "users upload their own program image" on storage.objects;
create policy "users upload their own program image"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'program-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users replace their own program image" on storage.objects;
create policy "users replace their own program image"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'program-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
