-- ═══════════════════════════════════════════════════════════════════════════
-- update_staff_profile gains full name / phone / photo — until now there was
-- no edit path anywhere in the app for a staff member's own identity fields
-- after they were created (Staff Details only edited title/notes; a coach is
-- just an existing staff member's coaching attributes, so its Edit dialog
-- had nowhere to send a name/phone/photo change either). Email is
-- deliberately excluded — it's the Supabase Auth login credential, and
-- changing it safely needs a separate admin-API edge function, not a plain
-- profile patch.
--
-- Along the way this also fixes a real bug: `p_title`/`p_notes` previously
-- overwrote unconditionally, so Staff Details' "Save notes" action (which
-- only ever sends `notes`, never `title`) silently wiped out any title the
-- person was given at creation every time notes were saved. `p_title`/
-- `p_notes` now only touch their column when the caller passes a non-null
-- value at all — `null` means "leave alone," an empty string means "clear
-- it." The three new identity fields use the simpler "set if given, else
-- leave alone" form — there's no legitimate reason to blank out someone's
-- name via this call, so that path isn't offered.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function update_staff_profile(
  p_facility_id uuid,
  p_user_id uuid,
  p_title text default null,
  p_notes text default null,
  p_full_name text default null,
  p_phone text default null,
  p_avatar_url text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'USERS_EDIT') then
    raise exception 'You don''t have permission to edit staff.' using errcode = '42501';
  end if;
  update facility_users
    set title = case when p_title is null then title else nullif(trim(p_title), '') end,
        notes = case when p_notes is null then notes else nullif(trim(p_notes), '') end,
        updated_at = now()
    where facility_id = p_facility_id and user_id = p_user_id;
  if not found then
    raise exception 'That staff member is not part of this facility.' using errcode = 'P0002';
  end if;

  update profiles
    set full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
        phone = coalesce(nullif(trim(p_phone), ''), phone),
        avatar_url = coalesce(nullif(trim(p_avatar_url), ''), avatar_url)
    where id = p_user_id
      and (p_full_name is not null or p_phone is not null or p_avatar_url is not null);

  perform log_security_event(p_facility_id, 'STAFF_PROFILE_UPDATED', 'Staff profile updated', p_user_id, null, '{}'::jsonb);
end;
$$;

grant execute on function update_staff_profile(uuid, uuid, text, text, text, text, text) to authenticated;
