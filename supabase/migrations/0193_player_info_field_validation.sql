-- ═══════════════════════════════════════════════════════════════════════════
-- Personal Information: the server checks every field too (the Player app already stops bad input while typing and on Save).
--
--   name / emergency contact name   2-60 characters; letters, spaces, . ' -   (no digits or symbols); spaces squashed
--   email                           max 100, a proper address (no spaces, no "..", a real domain ending), stored lower-case
--   date of birth                   1920-01-01 up to today
--   mobile numbers                  alternate + emergency: Indian mobile, 10 digits starting 6-9 (+91 / 0 / spaces / dashes are
--                                   accepted and dropped); never the player's own number; stored as the ten digits
--   relationship                    2-30 characters, letters, spaces, . ' -
--   address lines                   3-100 characters; letters, numbers, spaces and , . / # ' & ( ) -
--   PIN code                        6 digits, not starting with 0
--   about you                       max 200, no control characters
--   together                        the first address line and PIN code go together; an emergency contact has a name AND a number
-- Only the keys sent are checked. Messages are plain sentences (errcode 22023, which the app shows as they are).
-- ═══════════════════════════════════════════════════════════════════════════

-- A mobile number typed any way -> the ten digits, or an error. Empty -> null.
create or replace function _player_mobile(p_raw text, p_label text, p_own text)
returns text
language plpgsql
immutable
as $$
declare
  v_raw text := nullif(btrim(coalesce(p_raw, '')), '');
  v_digits text;
begin
  if v_raw is null then return null; end if;
  if v_raw ~ '[^0-9+ \-]' then
    raise exception 'Enter a valid 10-digit % (it starts with 6, 7, 8 or 9).', p_label using errcode = '22023';
  end if;
  v_digits := regexp_replace(v_raw, '\D', '', 'g');
  if length(v_digits) < 10 or length(v_digits) > 13 then
    raise exception 'Enter a valid 10-digit % (it starts with 6, 7, 8 or 9).', p_label using errcode = '22023';
  end if;
  v_digits := right(v_digits, 10);
  if v_digits !~ '^[6-9][0-9]{9}$' then
    raise exception 'Enter a valid 10-digit % (it starts with 6, 7, 8 or 9).', p_label using errcode = '22023';
  end if;
  if p_own is not null and right(regexp_replace(p_own, '\D', '', 'g'), 10) = v_digits then
    raise exception 'This is the number you signed in with. Please enter a different one.' using errcode = '22023';
  end if;
  return v_digits;
end;
$$;

-- A person's name or relationship: squashed, length-checked, no digits or symbols.
create or replace function _player_person_text(p_raw text, p_label text, p_min integer, p_max integer)
returns text
language plpgsql
immutable
as $$
declare
  v text := nullif(btrim(regexp_replace(coalesce(p_raw, ''), '\s+', ' ', 'g')), '');
begin
  if v is null then return null; end if;
  if length(v) < p_min then raise exception 'The % is too short.', p_label using errcode = '22023'; end if;
  if length(v) > p_max then raise exception 'The % is too long (at most % characters).', p_label, p_max using errcode = '22023'; end if;
  if v ~ '[0-9<>@#$%^&*()_+=\[\]{}|\\/~`!?:;,"]' or v ~ '^[^[:alpha:]]' then
    raise exception 'The % can only have letters, spaces, . '' and -.', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;

create or replace function _player_address_line(p_raw text, p_label text)
returns text
language plpgsql
immutable
as $$
declare
  v text := nullif(btrim(regexp_replace(coalesce(p_raw, ''), '\s+', ' ', 'g')), '');
begin
  if v is null then return null; end if;
  if length(v) < 3 then raise exception 'The % is too short.', p_label using errcode = '22023'; end if;
  if length(v) > 100 then raise exception 'The % is too long (at most 100 characters).', p_label using errcode = '22023'; end if;
  if v !~ '^[[:alnum:] ,./#''&()-]+$' then
    raise exception 'The % can only have letters, numbers, spaces and , . / # '' & ( ) -', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;


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
  v_about text;
  v_alt text;
  v_em_name text;
  v_em_rel text;
  v_em_phone text;
  v_l1 text;
  v_l2 text;
  v_pin text;
begin
  if v_uid is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  select * into v_cur from players where id = v_uid;
  if v_cur.id is null then raise exception 'No player profile' using errcode = 'P0002'; end if;
  p_patch := coalesce(p_patch, '{}'::jsonb);

  -- name
  v_name := v_cur.full_name;
  if p_patch ? 'fullName' then
    v_name := _player_person_text(p_patch ->> 'fullName', 'name', 2, 60);
    if v_name is null then raise exception 'Please enter your name.' using errcode = '22023'; end if;
  end if;

  -- email
  v_email := v_cur.email;
  if p_patch ? 'email' then
    v_email := lower(nullif(btrim(coalesce(p_patch ->> 'email', '')), ''));
    if v_email is not null then
      if length(v_email) > 100 then raise exception 'The email address is too long (at most 100 characters).' using errcode = '22023'; end if;
      if v_email !~ '^[a-z0-9._%+-]+@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$' or v_email like '%..%' or v_email like '.%' or v_email like '%.@%' then
        raise exception 'Please enter a valid email address.' using errcode = '22023';
      end if;
    end if;
  end if;

  -- date of birth
  v_dob := v_cur.dob;
  if p_patch ? 'dob' then
    t := nullif(btrim(coalesce(p_patch ->> 'dob', '')), '');
    if t is null then v_dob := null;
    else
      begin v_dob := t::date; exception when others then raise exception 'Please choose a valid date of birth.' using errcode = '22023'; end;
      if v_dob > current_date then raise exception 'The date of birth cannot be in the future.' using errcode = '22023'; end if;
      if v_dob < date '1920-01-01' then raise exception 'Please choose a valid date of birth.' using errcode = '22023'; end if;
    end if;
  end if;

  if p_patch ? 'gender' and nullif(p_patch ->> 'gender', '') is not null
     and (p_patch ->> 'gender') not in ('MALE', 'FEMALE', 'OTHER', 'PREFER_NOT_TO_SAY') then
    raise exception 'Unknown gender' using errcode = '22023';
  end if;

  -- preferred sports
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

  -- about you
  v_about := v_cur.about;
  if p_patch ? 'about' then
    v_about := nullif(btrim(coalesce(p_patch ->> 'about', '')), '');
    if v_about is not null then
      if length(v_about) > 200 then raise exception 'Keep "About you" under 200 characters.' using errcode = '22023'; end if;
      if v_about ~ '[\x01-\x08\x0B\x0C\x0E-\x1F]' then raise exception 'Please remove the special characters from "About you".' using errcode = '22023'; end if;
    end if;
  end if;

  -- contact numbers + emergency contact
  v_alt := v_cur.alt_phone;
  if p_patch ? 'altPhone' then v_alt := _player_mobile(p_patch ->> 'altPhone', 'alternate mobile number', v_cur.phone); end if;
  v_em_name := v_cur.emergency_name;
  if p_patch ? 'emergencyName' then v_em_name := _player_person_text(p_patch ->> 'emergencyName', 'contact name', 2, 60); end if;
  v_em_rel := v_cur.emergency_relation;
  if p_patch ? 'emergencyRelation' then v_em_rel := _player_person_text(p_patch ->> 'emergencyRelation', 'relationship', 2, 30); end if;
  v_em_phone := v_cur.emergency_phone;
  if p_patch ? 'emergencyPhone' then v_em_phone := _player_mobile(p_patch ->> 'emergencyPhone', 'contact mobile number', v_cur.phone); end if;
  if (p_patch ? 'emergencyName' or p_patch ? 'emergencyRelation' or p_patch ? 'emergencyPhone')
     and (v_em_name is not null or v_em_rel is not null or v_em_phone is not null) then
    if v_em_name is null then raise exception 'Please enter the contact name.' using errcode = '22023'; end if;
    if v_em_phone is null then raise exception 'Please enter the contact mobile number.' using errcode = '22023'; end if;
  end if;

  -- address
  v_l1 := v_cur.address_line1;
  if p_patch ? 'addressLine1' then v_l1 := _player_address_line(p_patch ->> 'addressLine1', 'address'); end if;
  v_l2 := v_cur.address_line2;
  if p_patch ? 'addressLine2' then v_l2 := _player_address_line(p_patch ->> 'addressLine2', 'address line'); end if;
  v_pin := v_cur.pincode;
  if p_patch ? 'pincode' then
    v_pin := nullif(btrim(coalesce(p_patch ->> 'pincode', '')), '');
    if v_pin is not null and v_pin !~ '^[1-9][0-9]{5}$' then raise exception 'PIN code must be 6 digits.' using errcode = '22023'; end if;
  end if;
  if (p_patch ? 'addressLine1' or p_patch ? 'addressLine2' or p_patch ? 'pincode')
     and (v_l1 is not null or v_l2 is not null or v_pin is not null) then
    if v_l1 is null then raise exception 'Please enter the address.' using errcode = '22023'; end if;
    if v_pin is null then raise exception 'Please enter the PIN code.' using errcode = '22023'; end if;
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
    about = v_about,
    alt_phone = v_alt,
    emergency_name = v_em_name,
    emergency_relation = v_em_rel,
    emergency_phone = v_em_phone,
    address_line1 = v_l1,
    address_line2 = v_l2,
    state = case when p_patch ? 'state' then nullif(btrim(coalesce(p_patch ->> 'state', '')), '') else state end,
    pincode = v_pin,
    id_doc_type = case when p_patch ? 'idDocType' then nullif(p_patch ->> 'idDocType', '') else id_doc_type end,
    id_doc_path = case when p_patch ? 'idDocPath' then v_doc_path else id_doc_path end,
    id_doc_name = case when p_patch ? 'idDocName' then nullif(btrim(coalesce(p_patch ->> 'idDocName', '')), '') else id_doc_name end
  where id = v_uid;

  return get_my_player_profile();
exception
  -- a value the table's own rules refuse (an unknown blood group, a T-shirt size that does not exist)
  when check_violation then
    raise exception 'Please check what you entered and try again' using errcode = '22023';
end;
$$;
revoke all on function update_my_player_info(jsonb) from public, anon;
grant execute on function update_my_player_info(jsonb) to authenticated;

notify pgrst, 'reload schema';
