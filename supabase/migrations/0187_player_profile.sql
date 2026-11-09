-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the "My Profile" screen.
--
--   players gets: player_code (the Player ID, "GA" + 8 digits), dob, gender, city, avatar_url
--   get_my_player_profile()           the full profile: everything get_my_player() gives plus the new fields
--   update_my_player_profile(...)     edit name, email, date of birth, gender, city and photo (own row only)
--   get_my_profile_stats()            the four numbers under the name: bookings, memberships, coaching, tournaments
--   get_my_payment_history(p_limit)   every payment and refund on the player's bookings, memberships and coaching, newest first
--   avatars bucket                    a public bucket; a player can only write inside their own folder (<uid>/...)
--
-- Nothing existing is changed: get_my_player() (sign-in) is untouched, so the app signs in whether or not this has been applied.
-- Re-runnable.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Player ID ────────────────────────────────────────────────────────────
create sequence if not exists player_code_seq start with 10000001;

alter table players
  add column if not exists player_code text,
  add column if not exists dob date,
  add column if not exists gender text,
  add column if not exists city text,
  add column if not exists avatar_url text;

alter table players drop constraint if exists players_gender_check;
alter table players add constraint players_gender_check
  check (gender is null or gender in ('MALE', 'FEMALE', 'OTHER', 'PREFER_NOT_TO_SAY'));
alter table players drop constraint if exists players_dob_check;
alter table players add constraint players_dob_check
  check (dob is null or (dob <= current_date and dob >= date '1900-01-01'));

-- existing players get an ID, new ones get it at sign-up
update players set player_code = 'GA' || nextval('player_code_seq')::text where player_code is null;
alter table players alter column player_code set default ('GA' || nextval('player_code_seq')::text);
create unique index if not exists players_player_code_idx on players (player_code);

-- ── The full profile ─────────────────────────────────────────────────────
create or replace function get_my_player_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'id', p.id, 'fullName', p.full_name, 'phone', p.phone, 'email', p.email,
           'playerCode', p.player_code, 'dob', p.dob, 'gender', p.gender, 'city', p.city, 'avatarUrl', p.avatar_url)
    from players p
   where p.id = auth.uid();
$$;
revoke all on function get_my_player_profile() from public, anon;
grant execute on function get_my_player_profile() to authenticated;

-- ── Edit the profile ─────────────────────────────────────────────────────
-- A null argument leaves that field as it is; an empty string clears an optional field. The phone number is never editable here:
-- it is the number that was verified at sign-in.
create or replace function update_my_player_profile(
  p_full_name text default null,
  p_email text default null,
  p_dob date default null,
  p_gender text default null,
  p_city text default null,
  p_avatar_url text default null,
  p_clear_dob boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := nullif(btrim(coalesce(p_full_name, '')), '');
  v_email text := nullif(btrim(coalesce(p_email, '')), '');
begin
  if v_uid is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  if p_full_name is not null and v_name is null then raise exception 'Please enter your name' using errcode = '22023'; end if;
  if length(coalesce(v_name, '')) > 100 then raise exception 'That name is too long' using errcode = '22023'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please enter a valid email address' using errcode = '22023';
  end if;
  if p_gender is not null and p_gender <> '' and p_gender not in ('MALE', 'FEMALE', 'OTHER', 'PREFER_NOT_TO_SAY') then
    raise exception 'Unknown gender' using errcode = '22023';
  end if;
  if p_avatar_url is not null and p_avatar_url <> '' and left(p_avatar_url, 8) <> 'https://' then
    raise exception 'Bad photo address' using errcode = '22023';
  end if;

  update players
     set full_name = coalesce(v_name, full_name),
         email = case when p_email is null then email else v_email end,
         dob = case when p_clear_dob then null else coalesce(p_dob, dob) end,
         gender = case when p_gender is null then gender else nullif(p_gender, '') end,
         city = case when p_city is null then city else nullif(btrim(p_city), '') end,
         avatar_url = case when p_avatar_url is null then avatar_url else nullif(p_avatar_url, '') end
   where id = v_uid;
  if not found then raise exception 'No player profile' using errcode = 'P0002'; end if;
  return get_my_player_profile();
end;
$$;
revoke all on function update_my_player_profile(text, text, date, text, text, text, boolean) from public, anon;
grant execute on function update_my_player_profile(text, text, date, text, text, text, boolean) to authenticated;

-- ── The four numbers ─────────────────────────────────────────────────────
-- bookings: every court booking of the player (not cancelled); memberships and coaching: every one they have ever had (not cancelled).
-- tournaments: null: tournaments are run in the separate GameAll Tournaments app, so there is nothing to count here.
create or replace function get_my_profile_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_people uuid[];
  v_guests uuid[];
begin
  if v_uid is null then return null; end if;
  select pl.phone into v_phone from players pl where pl.id = v_uid;
  select coalesce(array_agg(x.id), '{}') into v_people
    from (select m.id from members m where (v_phone is not null and normalize_phone(m.phone) = v_phone) or m.user_id = v_uid
          union select v_uid) x;
  select coalesce(array_agg(g.id), '{}') into v_guests from guest_players g where v_phone is not null and normalize_phone(g.phone) = v_phone;
  return jsonb_build_object(
    'bookings', (select count(*) from bookings b
                  where b.status::text not in ('cancelled', 'CANCELLED')
                    and (b.member_id = any (v_people)
                         or b.guest_player_id = any (v_guests)
                         or (b.customer_type = 'GUEST' and v_phone is not null and normalize_phone(b.guest_phone) = v_phone))),
    'memberships', (select count(*) from memberships ms where ms.member_id = any (v_people) and ms.status::text not in ('cancelled', 'CANCELLED')),
    'coaching', (select count(*) from coaching_enrollments e where e.member_id = any (v_people) and e.status::text not in ('cancelled', 'CANCELLED')),
    'tournaments', null);
end;
$$;
revoke all on function get_my_profile_stats() from public, anon;
grant execute on function get_my_profile_stats() to authenticated;

-- ── Payments, invoices and refunds ───────────────────────────────────────
--   kind     'payment' | 'refund'
--   source   'booking' | 'membership' | 'coaching'   and sourceId the id the receipt page opens
--   status   payments: PAID | PENDING | FAILED | REFUNDED       refunds: the refund's own status
--   amountInr is in rupees
create or replace function get_my_payment_history(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_people uuid[];
  v_guests uuid[];
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 200);
begin
  if v_uid is null then return '[]'::jsonb; end if;
  select pl.phone into v_phone from players pl where pl.id = v_uid;
  select coalesce(array_agg(x.id), '{}') into v_people
    from (select m.id from members m where (v_phone is not null and normalize_phone(m.phone) = v_phone) or m.user_id = v_uid
          union select v_uid) x;
  select coalesce(array_agg(g.id), '{}') into v_guests from guest_players g where v_phone is not null and normalize_phone(g.phone) = v_phone;

  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb order by t."at" desc)
      from (
        select * from (
          -- payments
          select 'payment'::text as kind,
                 case when py.booking_id is not null then 'booking'
                      when py.coaching_enrollment_id is not null then 'coaching'
                      else 'membership' end as source,
                 coalesce(py.booking_id, py.coaching_enrollment_id, py.membership_id) as "sourceId",
                 py.id as id,
                 py.amount_inr as "amountInr",
                 case py.status::text when 'paid' then 'PAID' when 'failed' then 'FAILED' when 'refunded' then 'REFUNDED' else 'PENDING' end as status,
                 coalesce(py.paid_at, py.created_at) as "at",
                 py.payment_method as method,
                 f.name as "venueName"
            from payments py
            join facilities f on f.id = py.facility_id
           where (py.booking_id is not null and exists (
                    select 1 from bookings b
                     where b.id = py.booking_id
                       and (b.member_id = any (v_people) or b.guest_player_id = any (v_guests)
                            or (b.customer_type = 'GUEST' and v_phone is not null and normalize_phone(b.guest_phone) = v_phone))))
              or (py.membership_id is not null and exists (
                    select 1 from memberships ms where ms.id = py.membership_id and ms.member_id = any (v_people)))
              or (py.coaching_enrollment_id is not null and exists (
                    select 1 from coaching_enrollments e where e.id = py.coaching_enrollment_id and e.member_id = any (v_people)))
          union all
          -- refunds, on the same payments
          select 'refund'::text,
                 case when py.booking_id is not null then 'booking'
                      when py.coaching_enrollment_id is not null then 'coaching'
                      else 'membership' end,
                 coalesce(py.booking_id, py.coaching_enrollment_id, py.membership_id),
                 r.id,
                 (r.amount_minor / 100)::integer,
                 r.status::text,
                 r.created_at,
                 null::text,
                 f.name
            from refunds r
            join payments py on py.id = r.transaction_id
            join facilities f on f.id = py.facility_id
           where (py.booking_id is not null and exists (
                    select 1 from bookings b
                     where b.id = py.booking_id
                       and (b.member_id = any (v_people) or b.guest_player_id = any (v_guests)
                            or (b.customer_type = 'GUEST' and v_phone is not null and normalize_phone(b.guest_phone) = v_phone))))
              or (py.membership_id is not null and exists (
                    select 1 from memberships ms where ms.id = py.membership_id and ms.member_id = any (v_people)))
              or (py.coaching_enrollment_id is not null and exists (
                    select 1 from coaching_enrollments e where e.id = py.coaching_enrollment_id and e.member_id = any (v_people)))
        ) u
        order by u."at" desc
        limit v_limit
      ) t
  ), '[]'::jsonb);
end;
$$;
revoke all on function get_my_payment_history(integer) from public, anon;
grant execute on function get_my_payment_history(integer) to authenticated;

-- ── Profile photos ───────────────────────────────────────────────────────
-- Public to read (the photo is shown as a normal image); a player can only add or replace files inside their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "avatars are publicly readable" on storage.objects;
create policy "avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "players upload their own avatar" on storage.objects;
create policy "players upload their own avatar"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "players replace their own avatar" on storage.objects;
create policy "players replace their own avatar"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "players delete their own avatar" on storage.objects;
create policy "players delete their own avatar"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
