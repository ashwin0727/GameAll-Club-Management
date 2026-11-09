-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the Personal Information page (Personal Details, Contact & Emergency, Address, Documents).
--
--   players gets   blood_group, tshirt_size, preferred_sports (sports.key list), playing_level, about (max 200),
--                  alt_phone, emergency_name / relation / phone, address_line1 / line2 / state / pincode (city already exists),
--                  id_doc_type / id_doc_path / id_doc_name (one ID proof; the file is private)
--   get_my_player_profile()          returns all of it
--   update_my_player_info(jsonb)     one save for the whole page: only the keys sent are changed; "" or null clears an optional field
--   list_platform_sports()           the sports a player can pick as preferred (GameAll's own list)
--   player-documents bucket          PRIVATE; a player reads and writes only inside their own folder (<uid>/...), 5 MB, jpg/png/webp/pdf
-- ═══════════════════════════════════════════════════════════════════════════

alter table players
  add column if not exists blood_group text,
  add column if not exists tshirt_size text,
  add column if not exists preferred_sports text[] not null default '{}',
  add column if not exists playing_level text,
  add column if not exists about text,
  add column if not exists alt_phone text,
  add column if not exists emergency_name text,
  add column if not exists emergency_relation text,
  add column if not exists emergency_phone text,
  add column if not exists address_line1 text,
  add column if not exists address_line2 text,
  add column if not exists state text,
  add column if not exists pincode text,
  add column if not exists id_doc_type text,
  add column if not exists id_doc_path text,
  add column if not exists id_doc_name text;

alter table players drop constraint if exists players_blood_group_check;
alter table players add constraint players_blood_group_check
  check (blood_group is null or blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'));
alter table players drop constraint if exists players_tshirt_size_check;
alter table players add constraint players_tshirt_size_check
  check (tshirt_size is null or tshirt_size in ('XS', 'S', 'M', 'L', 'XL', 'XXL'));
alter table players drop constraint if exists players_playing_level_check;
alter table players add constraint players_playing_level_check
  check (playing_level is null or playing_level in ('BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'PROFESSIONAL'));
alter table players drop constraint if exists players_about_check;
alter table players add constraint players_about_check check (about is null or length(about) <= 200);
alter table players drop constraint if exists players_pincode_check;
alter table players add constraint players_pincode_check check (pincode is null or pincode ~ '^[0-9]{6}$');
alter table players drop constraint if exists players_id_doc_type_check;
alter table players add constraint players_id_doc_type_check
  check (id_doc_type is null or id_doc_type in ('AADHAAR', 'PASSPORT', 'DRIVING_LICENCE', 'VOTER_ID', 'SCHOOL_ID', 'OTHER'));


-- ── the sports a player can prefer ───────────────────────────────────────
create or replace function list_platform_sports()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'name', s.name) order by s.sort_order, s.name), '[]'::jsonb)
    from sports s where s.is_active;
$$;
revoke all on function list_platform_sports() from public;
grant execute on function list_platform_sports() to anon, authenticated;


-- ── read ─────────────────────────────────────────────────────────────────
create or replace function get_my_player_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'id', p.id, 'fullName', p.full_name, 'phone', p.phone, 'email', p.email,
           'playerCode', p.player_code, 'dob', p.dob, 'gender', p.gender, 'city', p.city, 'avatarUrl', p.avatar_url,
           'bloodGroup', p.blood_group, 'tshirtSize', p.tshirt_size, 'preferredSports', to_jsonb(p.preferred_sports),
           'playingLevel', p.playing_level, 'about', p.about, 'altPhone', p.alt_phone,
           'emergencyName', p.emergency_name, 'emergencyRelation', p.emergency_relation, 'emergencyPhone', p.emergency_phone,
           'addressLine1', p.address_line1, 'addressLine2', p.address_line2, 'state', p.state, 'pincode', p.pincode,
           'idDocType', p.id_doc_type, 'idDocPath', p.id_doc_path, 'idDocName', p.id_doc_name)
    from players p
   where p.id = auth.uid();
$$;
revoke all on function get_my_player_profile() from public, anon;
grant execute on function get_my_player_profile() to authenticated;


-- ── save the page ────────────────────────────────────────────────────────
-- p_patch keys (all optional): fullName, email, dob (yyyy-mm-dd), gender, city, bloodGroup, tshirtSize, preferredSports (array of
-- sports.key), playingLevel, about, altPhone, emergencyName, emergencyRelation, emergencyPhone, addressLine1, addressLine2, state,
-- pincode, idDocType, idDocPath, idDocName. A key that is present with "" / null clears that optional field; a missing key is left.
create or replace function update_my_player_info(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cur players;
  t text;
  v_name text;
  v_email text;
  v_dob date;
  v_sports text[];
  v_bad text;
  v_doc_path text;
begin
  if v_uid is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  select * into v_cur from players where id = v_uid;
  if v_cur.id is null then raise exception 'No player profile' using errcode = 'P0002'; end if;
  p_patch := coalesce(p_patch, '{}'::jsonb);

  v_name := v_cur.full_name;
  if p_patch ? 'fullName' then
    v_name := nullif(btrim(coalesce(p_patch ->> 'fullName', '')), '');
    if v_name is null then raise exception 'Please enter your name' using errcode = '22023'; end if;
    if length(v_name) > 100 then raise exception 'That name is too long' using errcode = '22023'; end if;
  end if;

  v_email := v_cur.email;
  if p_patch ? 'email' then
    v_email := nullif(btrim(coalesce(p_patch ->> 'email', '')), '');
    if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Please enter a valid email address' using errcode = '22023';
    end if;
  end if;

  v_dob := v_cur.dob;
  if p_patch ? 'dob' then
    t := nullif(btrim(coalesce(p_patch ->> 'dob', '')), '');
    if t is null then v_dob := null;
    else
      begin v_dob := t::date; exception when others then raise exception 'Please enter a valid date of birth' using errcode = '22023'; end;
      if v_dob > current_date or v_dob < date '1900-01-01' then raise exception 'Please enter a valid date of birth' using errcode = '22023'; end if;
    end if;
  end if;

  if p_patch ? 'gender' and nullif(p_patch ->> 'gender', '') is not null
     and (p_patch ->> 'gender') not in ('MALE', 'FEMALE', 'OTHER', 'PREFER_NOT_TO_SAY') then
    raise exception 'Unknown gender' using errcode = '22023';
  end if;

  v_sports := v_cur.preferred_sports;
  if p_patch ? 'preferredSports' then
    if jsonb_typeof(p_patch -> 'preferredSports') = 'array' then
      select coalesce(array_agg(distinct x), '{}') into v_sports from jsonb_array_elements_text(p_patch -> 'preferredSports') x;
    else
      v_sports := '{}';
    end if;
    select x into v_bad from unnest(v_sports) x where not exists (select 1 from sports s where s.key = x and s.is_active) limit 1;
    if v_bad is not null then raise exception 'Unknown sport' using errcode = '22023'; end if;
    if coalesce(array_length(v_sports, 1), 0) > 10 then raise exception 'Please choose up to 10 sports' using errcode = '22023'; end if;
  end if;

  -- the ID proof file must be inside the player's own folder
  if p_patch ? 'idDocPath' then
    v_doc_path := nullif(btrim(coalesce(p_patch ->> 'idDocPath', '')), '');
    if v_doc_path is not null and left(v_doc_path, length(v_uid::text) + 1) <> v_uid::text || '/' then
      raise exception 'Bad document address' using errcode = '22023';
    end if;
  end if;

  update players set
    full_name = v_name,
    email = v_email,
    dob = v_dob,
    gender = case when p_patch ? 'gender' then nullif(p_patch ->> 'gender', '') else gender end,
    city = case when p_patch ? 'city' then nullif(btrim(coalesce(p_patch ->> 'city', '')), '') else city end,
    blood_group = case when p_patch ? 'bloodGroup' then nullif(p_patch ->> 'bloodGroup', '') else blood_group end,
    tshirt_size = case when p_patch ? 'tshirtSize' then nullif(p_patch ->> 'tshirtSize', '') else tshirt_size end,
    preferred_sports = v_sports,
    playing_level = case when p_patch ? 'playingLevel' then nullif(p_patch ->> 'playingLevel', '') else playing_level end,
    about = case when p_patch ? 'about' then nullif(btrim(coalesce(p_patch ->> 'about', '')), '') else about end,
    alt_phone = case when p_patch ? 'altPhone' then nullif(btrim(coalesce(p_patch ->> 'altPhone', '')), '') else alt_phone end,
    emergency_name = case when p_patch ? 'emergencyName' then nullif(btrim(coalesce(p_patch ->> 'emergencyName', '')), '') else emergency_name end,
    emergency_relation = case when p_patch ? 'emergencyRelation' then nullif(btrim(coalesce(p_patch ->> 'emergencyRelation', '')), '') else emergency_relation end,
    emergency_phone = case when p_patch ? 'emergencyPhone' then nullif(btrim(coalesce(p_patch ->> 'emergencyPhone', '')), '') else emergency_phone end,
    address_line1 = case when p_patch ? 'addressLine1' then nullif(btrim(coalesce(p_patch ->> 'addressLine1', '')), '') else address_line1 end,
    address_line2 = case when p_patch ? 'addressLine2' then nullif(btrim(coalesce(p_patch ->> 'addressLine2', '')), '') else address_line2 end,
    state = case when p_patch ? 'state' then nullif(btrim(coalesce(p_patch ->> 'state', '')), '') else state end,
    pincode = case when p_patch ? 'pincode' then nullif(btrim(coalesce(p_patch ->> 'pincode', '')), '') else pincode end,
    id_doc_type = case when p_patch ? 'idDocType' then nullif(p_patch ->> 'idDocType', '') else id_doc_type end,
    id_doc_path = case when p_patch ? 'idDocPath' then v_doc_path else id_doc_path end,
    id_doc_name = case when p_patch ? 'idDocName' then nullif(btrim(coalesce(p_patch ->> 'idDocName', '')), '') else id_doc_name end
  where id = v_uid;

  return get_my_player_profile();
exception
  -- a value the table's own rules refuse (a 7-digit PIN code, a 201-character "about you", an unknown blood group)
  when check_violation then
    raise exception 'Please check what you entered and try again' using errcode = '22023';
end;
$$;
revoke all on function update_my_player_info(jsonb) from public, anon;
grant execute on function update_my_player_info(jsonb) to authenticated;


-- ── the ID proof file: private ───────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('player-documents', 'player-documents', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

drop policy if exists "players read their own documents" on storage.objects;
create policy "players read their own documents"
  on storage.objects for select to authenticated
  using (bucket_id = 'player-documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "players upload their own documents" on storage.objects;
create policy "players upload their own documents"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'player-documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "players replace their own documents" on storage.objects;
create policy "players replace their own documents"
  on storage.objects for update to authenticated
  using (bucket_id = 'player-documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "players delete their own documents" on storage.objects;
create policy "players delete their own documents"
  on storage.objects for delete to authenticated
  using (bucket_id = 'player-documents' and (storage.foldername(name))[1] = auth.uid()::text);

notify pgrst, 'reload schema';
