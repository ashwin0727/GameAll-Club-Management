  -- Deleting a PLAYER's account must also stop the AutoPay mandates (membership and monthly coaching) set up in their name.
  --
  -- 0163's account_deletion_plan only looked at the club a person OWNS. A player owns no club, so their own UPI AutoPay mandates were
  -- never cancelled and kept charging a person who no longer had an account. This adds the player's own recurring payments to the
  -- plan: every membership / coaching AutoPay of a member whose phone number is the player's phone number (the same match the app
  -- itself uses, normalize_phone). Nothing else about the plan changes.

  create or replace function account_deletion_plan(p_user uuid)
  returns jsonb
  language plpgsql stable security definer set search_path = public
  as $$
  declare
    v_facilities uuid[];
    v_subs text[];
    v_orphans uuid[];
    v_phone text;
  begin
    select coalesce(array_agg(id), '{}') into v_facilities from facilities where owner_id = p_user;
    select normalize_phone(phone) into v_phone from players where id = p_user;

    select coalesce(array_agg(distinct s), '{}') into v_subs from (
      select razorpay_subscription_id as s from facility_subscriptions where facility_id = any (v_facilities)
      union all select razorpay_subscription_id from membership_subscriptions where facility_id = any (v_facilities)
      union all select razorpay_subscription_id from coaching_enrollment_billing where facility_id = any (v_facilities)
      union all select razorpay_subscription_id from plan_checkouts where facility_id = any (v_facilities)
      -- a player's own mandates
      union all select ms.razorpay_subscription_id
        from membership_subscriptions ms join members m on m.id = ms.member_id
        where v_phone is not null and normalize_phone(m.phone) = v_phone
      union all select b.razorpay_subscription_id
        from coaching_enrollment_billing b
        join coaching_enrollments e on e.id = b.enrollment_id
        join members m on m.id = e.member_id
        where v_phone is not null and normalize_phone(m.phone) = v_phone
    ) q where s is not null;

    -- Staff who belong only to the facilities being deleted would be left with an account and nothing to open.
    select coalesce(array_agg(distinct fu.user_id), '{}') into v_orphans
    from facility_users fu
    where fu.facility_id = any (v_facilities) and fu.user_id <> p_user
      and not exists (select 1 from facility_users o where o.user_id = fu.user_id and o.facility_id <> all (v_facilities))
      and not exists (select 1 from facilities f where f.owner_id = fu.user_id and f.id <> all (v_facilities));

    return jsonb_build_object('facilities', to_jsonb(v_facilities), 'razorpaySubscriptions', to_jsonb(v_subs), 'orphanStaff', to_jsonb(v_orphans));
  end;
  $$;

  revoke all on function account_deletion_plan(uuid) from public, anon, authenticated;
  grant execute on function account_deletion_plan(uuid) to service_role;
