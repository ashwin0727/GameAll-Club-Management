-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Details page — Phase 7.
--
-- get_membership_detail(p_membership_id) — one read for the full detail
-- screen: the member, the membership's own fields, the latest membership
-- payment, the referral member's name, who created it, the reserved
-- time-slot (if any), and a derived activity timeline. Returned as a single
-- jsonb document. SECURITY INVOKER — the caller's RLS on
-- memberships / members / payments already scopes it to their facility.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_membership_detail(p_membership_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  m memberships;
  mem members;
  mp membership_plans;
  pay payments;
  ref_name text;
  creator_name text;
  slot_batch membership_batches;
  slot_court text;
  is_paid boolean;
  timeline jsonb := '[]'::jsonb;
begin
  select * into m from memberships where id = p_membership_id;
  if m.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;

  select * into mem from members where id = m.member_id;
  if m.plan_id is not null then
    select * into mp from membership_plans where id = m.plan_id;
  end if;

  -- Latest payment for this membership.
  select * into pay from payments
    where membership_id = m.id
    order by coalesce(paid_at, created_at) desc
    limit 1;

  is_paid := coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0) = 0
    or exists (select 1 from payments pp where pp.membership_id = m.id and pp.status = 'paid');

  if m.referral_member_id is not null then
    select full_name into ref_name from members where id = m.referral_member_id;
  end if;
  if m.created_by is not null then
    select full_name into creator_name from profiles where id = m.created_by;
  end if;

  -- Reserved time slot, if the member is enrolled in a batch.
  select b.* into slot_batch
  from membership_batch_members bm
  join membership_batches b on b.id = bm.batch_id
  where bm.membership_id = m.id
  order by bm.created_at
  limit 1;
  if slot_batch.id is not null then
    select name into slot_court from courts where id = slot_batch.court_id;
  end if;

  -- Derived timeline (mirrors the design's Activity Timeline).
  timeline := timeline || jsonb_build_object(
    'label', 'Membership created',
    'actor', coalesce(creator_name, 'Self registered'),
    'at', m.created_at
  );
  if pay.id is not null and pay.status = 'paid' then
    timeline := timeline || jsonb_build_object(
      'label', 'Payment received',
      'actor', coalesce(pay.payment_method, 'Payment'),
      'at', coalesce(pay.paid_at, pay.created_at)
    );
  end if;
  if m.status = 'active' and is_paid then
    timeline := timeline || jsonb_build_object(
      'label', 'Membership activated',
      'actor', 'System',
      'at', coalesce(pay.paid_at, m.created_at)
    );
  end if;

  return jsonb_build_object(
    'membershipId', m.id,
    'facilityId', m.facility_id,
    'displayStatus', case
      when m.status = 'cancelled' or m.end_date < current_date then 'inactive'
      when not is_paid then 'payment_not_initiated'
      else 'active'
    end,
    'member', jsonb_build_object(
      'id', mem.id,
      'fullName', mem.full_name,
      'phone', mem.phone,
      'email', mem.email,
      'dateOfBirth', mem.date_of_birth,
      'gender', mem.gender,
      'address', mem.address,
      'status', mem.status,
      'memberSince', mem.created_at
    ),
    'membership', jsonb_build_object(
      'name', coalesce(m.name, mp.name, 'Membership'),
      'membershipType', m.membership_type,
      'rawStatus', m.status,
      'startDate', m.start_date,
      'endDate', m.end_date,
      'durationDays', m.duration_days,
      'maxFamilyMembers', m.max_family_members,
      'description', m.description,
      'membershipFeeInr', coalesce(m.membership_fee_inr, mp.price_inr, 0),
      'registrationFeeInr', coalesce(m.registration_fee_inr, 0),
      'gstPercent', coalesce(m.gst_percent, 0),
      'totalAmountInr', coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0),
      'monthlyPriceInr', coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0),
      'autoRenew', m.auto_renew,
      'createdAt', m.created_at
    ),
    'payment', case when pay.id is null then null else jsonb_build_object(
      'amountInr', pay.amount_inr,
      'status', pay.status,
      'method', pay.payment_method,
      'paidAt', pay.paid_at,
      'createdAt', pay.created_at,
      'transactionId', pay.razorpay_payment_id
    ) end,
    'referralName', ref_name,
    'createdByName', creator_name,
    'discoverySource', m.discovery_source,
    'paymentReference', m.payment_reference,
    'notes', m.notes,
    'slot', case when slot_batch.id is null then null else jsonb_build_object(
      'courtName', slot_court,
      'daysOfWeek', slot_batch.days_of_week,
      'startTime', slot_batch.start_time,
      'endTime', slot_batch.end_time
    ) end,
    'timeline', timeline
  );
end;
$$;

grant execute on function get_membership_detail(uuid) to authenticated;