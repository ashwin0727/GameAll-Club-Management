-- ═══════════════════════════════════════════════════════════════════════════
-- Profile photo uploads — first consumer is the Add Coach wizard's "+ New
-- person" path (Coaching v1), but this is a person-level photo (profiles.
-- avatar_url), not coaching-specific, so it's a general-purpose bucket any
-- future "create a person" flow can reuse rather than a coaching one.
--
-- Public bucket, same shape as facility-logos (0057): reads are open (an
-- avatar is shown all over the app), writes are scoped to a folder named
-- after the uploader's own user id.
-- ═══════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "avatars are publicly readable" on storage.objects;
create policy "avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "users upload their own avatar" on storage.objects;
create policy "users upload their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users replace their own avatar" on storage.objects;
create policy "users replace their own avatar"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
