-- ═══════════════════════════════════════════════════════════════════════════
-- Platform admin — GameAll's own back office.
--
-- One account, admin@gameall.co, can see every facility that has registered, review the bank / UPI details owners add for
-- payouts (and mark them Verified), and track the online (Razorpay) payments taken for each facility, marking them Settled
-- once the money has been sent on.
--
-- Who is the platform admin: the signed-in user whose confirmed email is admin@gameall.co. Nothing else widens access
-- (profiles.role = 'admin' is just "owner account" — see 0118), and nobody can sign up as this address without receiving
-- the confirmation email. The account itself is created in the Supabase dashboard (Authentication → Add user, Auto Confirm)
-- so the password is chosen by GameAll.
--
-- Every function below is SECURITY DEFINER and starts with require_platform_admin(); no table is opened to anyone.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function is_platform_admin()
returns boolean
language sql stable security definer set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid() and lower(u.email) = 'admin@gameall.co' and u.email_confirmed_at is not null
  );
$$;
grant execute on function is_platform_admin() to authenticated;

create or replace function require_platform_admin()
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_platform_admin() then
    raise exception 'Platform administrators only.' using errcode = '42501';
  end if;
end;
$$;

-- ── Payout verification ───────────────────────────────────────────────────────
alter table facility_payout_methods add column if not exists verified_by uuid references auth.users (id);

-- Same guard as 0148, plus: the platform admin may set the verification fields (and only they, besides the service role).
create or replace function guard_payout_method_verification()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or is_platform_admin() then
    if new.verification_status = 'VERIFIED' then
      new.verified_at := coalesce(new.verified_at, now());
      new.verified_by := coalesce(new.verified_by, auth.uid());
    else
      new.verified_at := null;
      new.verified_by := null;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.verification_status := 'PENDING';
    new.verified_at := null;
    new.verified_by := null;
    new.verification_note := null;
  else
    if new.verification_status is distinct from old.verification_status
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by
       or new.verification_note is distinct from old.verification_note then
      raise exception 'Verification is managed by GameAll' using errcode = '42501';
    end if;
    if new.method_type is distinct from old.method_type
       or new.account_holder_name is distinct from old.account_holder_name
       or new.bank_name is distinct from old.bank_name
       or new.account_number is distinct from old.account_number
       or new.ifsc is distinct from old.ifsc
       or new.upi_id is distinct from old.upi_id then
      new.verification_status := 'PENDING';
      new.verified_at := null;
      new.verified_by := null;
      new.verification_note := null;
    end if;
  end if;
  return new;
end;
$$;

-- ── Settled payments ───────────────────────────────────────────────────────────
-- A payment is "settled" once GameAll has sent that money on to the facility.
create table if not exists payment_settlements (
  payment_id  uuid primary key references payments (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  settled_at  timestamptz not null default now(),
  settled_by  uuid references auth.users (id),
  note        text
);
create index if not exists payment_settlements_facility_idx on payment_settlements (facility_id, settled_at desc);
alter table payment_settlements enable row level security;   -- no policies: only the functions below read or write it

-- An online payment is one that went through Razorpay (checkout, payment link, UPI AutoPay). Cash and other offline entries
-- never carry a Razorpay payment id.
create or replace function _is_online_payment(p payments)
returns boolean
language sql immutable
as $$ select p.razorpay_payment_id is not null and p.status::text in ('paid', 'refunded'); $$;

-- ── Home: totals ───────────────────────────────────────────────────────────────
create or replace function admin_overview()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v jsonb;
begin
  perform require_platform_admin();
  select jsonb_build_object(
    'facilities', (select count(*) from facilities),
    'onboarded', (select count(*) from facilities where onboarding_step::text = 'COMPLETED'),
    'inProgress', (select count(*) from facilities where onboarding_step::text <> 'COMPLETED'),
    'courts', (select count(*) from courts where not archived),
    'sports', (select count(*) from facility_sports where is_active),
    'activeMemberships', (select count(*) from memberships where status::text = 'active'),
    'activeStudents', (select count(*) from coaching_enrollments where status::text = 'ACTIVE'),
    'payoutsPending', (select count(*) from facility_payout_methods where verification_status = 'PENDING'),
    'unsettledInr', coalesce((select sum(p.amount_inr) from payments p
        where _is_online_payment(p) and p.status::text = 'paid'
          and not exists (select 1 from payment_settlements s where s.payment_id = p.id)), 0),
    'settledInr', coalesce((select sum(p.amount_inr) from payments p join payment_settlements s on s.payment_id = p.id), 0)
  ) into v;
  return v;
end;
$$;
grant execute on function admin_overview() to authenticated;

-- ── Home: facility list ────────────────────────────────────────────────────────
create or replace function admin_list_facilities(p_search text default null, p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_rows jsonb;
  v_total bigint;
  v_q text := nullif(btrim(coalesce(p_search, '')), '');
begin
  perform require_platform_admin();
  select count(*) into v_total
    from facilities f left join profiles o on o.id = f.owner_id
    where v_q is null or f.name ilike '%' || v_q || '%' or f.city ilike '%' || v_q || '%'
       or o.full_name ilike '%' || v_q || '%' or o.email ilike '%' || v_q || '%' or f.business_phone ilike '%' || v_q || '%';

  select coalesce(jsonb_agg(r order by (r->>'createdAt') desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', f.id,
      'name', f.name,
      'city', f.city,
      'state', f.state,
      'status', f.status::text,
      'onboardingStep', f.onboarding_step::text,
      'createdAt', f.created_at,
      'ownerName', o.full_name,
      'ownerEmail', o.email,
      'ownerPhone', coalesce(f.business_phone, o.phone),
      'sports', (select count(*) from facility_sports fs where fs.facility_id = f.id and fs.is_active),
      'courts', (select count(*) from courts c where c.facility_id = f.id and not c.archived),
      'activeMemberships', (select count(*) from memberships m where m.facility_id = f.id and m.status::text = 'active'),
      'activeStudents', (select count(*) from coaching_enrollments e where e.facility_id = f.id and e.status::text = 'ACTIVE'),
      'payoutVerified', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'VERIFIED'),
      'payoutPending', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'PENDING'),
      'planName', (select s.plan_name from facility_subscriptions s where s.facility_id = f.id)
    ) as r
    from facilities f left join profiles o on o.id = f.owner_id
    where v_q is null or f.name ilike '%' || v_q || '%' or f.city ilike '%' || v_q || '%'
       or o.full_name ilike '%' || v_q || '%' or o.email ilike '%' || v_q || '%' or f.business_phone ilike '%' || v_q || '%'
    order by f.created_at desc
    limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) t;

  return jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;
grant execute on function admin_list_facilities(text, integer, integer) to authenticated;

-- ── Home: one facility, everything ───────────────────────────────────────────────
create or replace function admin_get_facility(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  f facilities;
  o profiles;
begin
  perform require_platform_admin();
  select * into f from facilities where id = p_facility_id;
  if f.id is null then
    raise exception 'Facility not found.' using errcode = 'P0002';
  end if;
  select * into o from profiles where id = f.owner_id;

  return jsonb_build_object(
    'facility', jsonb_build_object(
      'id', f.id, 'name', f.name, 'type', coalesce(f.custom_facility_type, f.facility_type::text), 'status', f.status::text,
      'onboardingStep', f.onboarding_step::text, 'createdAt', f.created_at, 'onboardingCompletedAt', f.onboarding_completed_at,
      'businessEmail', f.business_email, 'businessPhone', f.business_phone,
      'address', concat_ws(', ', f.address_line_1, f.address_line_2, f.area, f.city, f.state, f.postal_code),
      'city', f.city, 'timezone', f.timezone, 'description', f.description
    ),
    'owner', jsonb_build_object('name', o.full_name, 'email', o.email, 'phone', o.phone),
    'sports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', coalesce(fs.custom_sport_name, s.name),
        'active', fs.is_active,
        'courts', (select count(*) from courts c where c.facility_sport_id = fs.id and not c.archived)
      ) order by coalesce(fs.custom_sport_name, s.name))
      from facility_sports fs left join sports s on s.id = fs.sport_id where fs.facility_id = f.id), '[]'::jsonb),
    'courts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', c.name, 'sport', coalesce(fs.custom_sport_name, s.name), 'surface', c.surface,
        'hourlyRateInr', c.hourly_rate_inr, 'status', c.status::text, 'bookingEnabled', c.booking_enabled
      ) order by c.display_order, c.name)
      from courts c left join facility_sports fs on fs.id = c.facility_sport_id left join sports s on s.id = fs.sport_id
      where c.facility_id = f.id and not c.archived), '[]'::jsonb),
    'memberships', jsonb_build_object(
      'plans', (select count(*) from membership_plans mp where mp.facility_id = f.id and mp.is_active),
      'active', (select count(*) from memberships m where m.facility_id = f.id and m.status::text = 'active'),
      'pending', (select count(*) from memberships m where m.facility_id = f.id and m.status::text = 'pending'),
      'members', (select count(*) from members mb where mb.facility_id = f.id),
      'collectedInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and p.membership_id is not null and p.status::text = 'paid'), 0)
    ),
    'coaching', jsonb_build_object(
      'coaches', (select count(*) from coaches c where c.facility_id = f.id),
      'programs', (select count(*) from coaching_programs cp where cp.facility_id = f.id),
      'activeStudents', (select count(*) from coaching_enrollments e where e.facility_id = f.id and e.status::text = 'ACTIVE'),
      'collectedInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and p.coaching_enrollment_id is not null and p.status::text = 'paid'), 0)
    ),
    'payments', jsonb_build_object(
      'onlineCount', (select count(*) from payments p where p.facility_id = f.id and _is_online_payment(p) and p.status::text = 'paid'),
      'onlineInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and _is_online_payment(p) and p.status::text = 'paid'), 0),
      'offlineCount', (select count(*) from payments p where p.facility_id = f.id and p.razorpay_payment_id is null and p.status::text = 'paid'),
      'offlineInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and p.razorpay_payment_id is null and p.status::text = 'paid'), 0),
      'refundedInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and p.status::text = 'refunded'), 0),
      'settledInr', coalesce((select sum(p.amount_inr) from payments p join payment_settlements s on s.payment_id = p.id where p.facility_id = f.id), 0),
      'unsettledInr', coalesce((select sum(p.amount_inr) from payments p where p.facility_id = f.id and _is_online_payment(p) and p.status::text = 'paid'
          and not exists (select 1 from payment_settlements s where s.payment_id = p.id)), 0)
    ),
    'plan', (select jsonb_build_object('name', s.plan_name, 'status', s.status, 'interval', s.billing_interval, 'priceMinor', s.price_minor, 'validTill', s.valid_till)
             from facility_subscriptions s where s.facility_id = f.id),
    'payoutMethods', coalesce((
      select jsonb_agg(jsonb_build_object('id', pm.id, 'type', pm.method_type, 'verification', pm.verification_status, 'primary', pm.is_primary) order by pm.is_primary desc, pm.created_at)
      from facility_payout_methods pm where pm.facility_id = f.id), '[]'::jsonb)
  );
end;
$$;
grant execute on function admin_get_facility(uuid) to authenticated;

-- ── Payout page ──────────────────────────────────────────────────────────────────
create or replace function admin_list_payout_facilities()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', f.id, 'name', f.name, 'city', f.city, 'ownerName', o.full_name, 'ownerEmail', o.email,
      'total', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id),
      'pending', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'PENDING'),
      'verified', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'VERIFIED'),
      'rejected', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'REJECTED'),
      'updatedAt', (select max(pm.updated_at) from facility_payout_methods pm where pm.facility_id = f.id)
    ) order by (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'PENDING') desc, f.name)
    from facilities f left join profiles o on o.id = f.owner_id), '[]'::jsonb);
end;
$$;
grant execute on function admin_list_payout_facilities() to authenticated;

create or replace function admin_list_payout_methods(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return jsonb_build_object(
    'facility', (select jsonb_build_object('id', f.id, 'name', f.name, 'city', f.city, 'ownerName', o.full_name, 'ownerEmail', o.email, 'ownerPhone', coalesce(f.business_phone, o.phone))
                 from facilities f left join profiles o on o.id = f.owner_id where f.id = p_facility_id),
    'methods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pm.id, 'type', pm.method_type, 'accountHolderName', pm.account_holder_name, 'bankName', pm.bank_name,
        'accountNumber', pm.account_number, 'ifsc', pm.ifsc, 'upiId', pm.upi_id, 'primary', pm.is_primary,
        'verification', pm.verification_status, 'verifiedAt', pm.verified_at, 'note', pm.verification_note,
        'createdAt', pm.created_at, 'updatedAt', pm.updated_at
      ) order by pm.is_primary desc, pm.created_at)
      from facility_payout_methods pm where pm.facility_id = p_facility_id), '[]'::jsonb)
  );
end;
$$;
grant execute on function admin_list_payout_methods(uuid) to authenticated;

-- Verify or reject a method. The owner sees the result as the Verified badge on their Payment Methods.
create or replace function admin_review_payout_method(p_method_id uuid, p_status text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  if p_status not in ('VERIFIED', 'REJECTED', 'PENDING') then
    raise exception 'Choose Verified, Rejected or Pending.' using errcode = '22023';
  end if;
  if p_status = 'REJECTED' and nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Say why it was rejected so the owner can fix it.' using errcode = '22023';
  end if;
  update facility_payout_methods
     set verification_status = p_status, verification_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now()
   where id = p_method_id;
  if not found then
    raise exception 'Payout method not found.' using errcode = 'P0002';
  end if;
end;
$$;
grant execute on function admin_review_payout_method(uuid, text, text) to authenticated;

-- ── Transactions page ────────────────────────────────────────────────────────────
create or replace function admin_list_transaction_facilities()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return coalesce((
    select jsonb_agg(row order by (row->>'recentInr')::numeric desc, row->>'name') from (
      select jsonb_build_object(
        'id', f.id, 'name', f.name, 'city', f.city,
        'recentCount', count(*) filter (where p.id is not null and s.payment_id is null and p.status::text = 'paid'),
        'recentInr', coalesce(sum(p.amount_inr) filter (where s.payment_id is null and p.status::text = 'paid'), 0),
        'settledCount', count(*) filter (where s.payment_id is not null),
        'settledInr', coalesce(sum(p.amount_inr) filter (where s.payment_id is not null), 0),
        'lastAt', max(coalesce(p.paid_at, p.created_at))
      ) as row
      from facilities f
      left join payments p on p.facility_id = f.id and _is_online_payment(p)
      left join payment_settlements s on s.payment_id = p.id
      group by f.id, f.name, f.city
    ) t), '[]'::jsonb);
end;
$$;
grant execute on function admin_list_transaction_facilities() to authenticated;

create or replace function admin_list_transactions(p_facility_id uuid, p_view text default 'recent', p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_rows jsonb;
  v_total bigint;
  v_amount numeric;
begin
  perform require_platform_admin();
  if p_view not in ('recent', 'settled') then
    raise exception 'View must be recent or settled.' using errcode = '22023';
  end if;

  select count(*), coalesce(sum(p.amount_inr), 0) into v_total, v_amount
    from payments p left join payment_settlements s on s.payment_id = p.id
    where p.facility_id = p_facility_id and _is_online_payment(p)
      and ((p_view = 'settled' and s.payment_id is not null) or (p_view = 'recent' and s.payment_id is null));

  select coalesce(jsonb_agg(r order by (r->>'at') desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', p.id,
      'at', coalesce(p.paid_at, p.created_at),
      'amountInr', p.amount_inr,
      'status', p.status::text,
      'method', coalesce(p.payment_method, 'Razorpay'),
      'razorpayPaymentId', p.razorpay_payment_id,
      'razorpayOrderId', p.razorpay_order_id,
      'source', case
        when p.coaching_enrollment_id is not null then 'Coaching'
        when p.membership_id is not null then 'Membership'
        when p.booking_id is not null then 'Booking'
        else 'Other' end,
      'payer', coalesce(g.name, mb.full_name),
      'settledAt', s.settled_at,
      'settledNote', s.note
    ) as r
    from payments p
    left join payment_settlements s on s.payment_id = p.id
    left join guest_players g on g.id = p.guest_player_id
    left join members mb on mb.id = p.member_id
    where p.facility_id = p_facility_id and _is_online_payment(p)
      and ((p_view = 'settled' and s.payment_id is not null) or (p_view = 'recent' and s.payment_id is null))
    order by coalesce(p.paid_at, p.created_at) desc
    limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) t;

  return jsonb_build_object('total', v_total, 'totalInr', v_amount, 'rows', v_rows);
end;
$$;
grant execute on function admin_list_transactions(uuid, text, integer, integer) to authenticated;

-- Mark online payments as Settled (the money has been sent to the facility). Only paid payments qualify. Returns how many
-- were newly settled.
create or replace function admin_mark_settled(p_payment_ids uuid[], p_note text default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  perform require_platform_admin();
  insert into payment_settlements (payment_id, facility_id, settled_by, note)
  select p.id, p.facility_id, auth.uid(), nullif(btrim(coalesce(p_note, '')), '')
  from payments p
  where p.id = any (p_payment_ids) and _is_online_payment(p) and p.status::text = 'paid'
  on conflict (payment_id) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function admin_mark_settled(uuid[], text) to authenticated;

-- Undo a mistaken click.
create or replace function admin_unsettle(p_payment_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  delete from payment_settlements where payment_id = p_payment_id;
end;
$$;
grant execute on function admin_unsettle(uuid) to authenticated;

-- First sign-in: if admin@gameall.co already exists, its owner is asked to choose their own password straight away (the same
-- forced "set a new password" screen staff use). If the account is created after this migration, run once:
--   update profiles set must_reset_password = true where lower(email) = 'admin@gameall.co';
update profiles set must_reset_password = true where lower(email) = 'admin@gameall.co';
