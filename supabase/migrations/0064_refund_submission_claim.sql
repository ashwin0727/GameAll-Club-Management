-- ═══════════════════════════════════════════════════════════════════════════
-- Refund submission claim — closes the concurrent-refund-submission race.
--
-- Before: _shared/submit-refund.ts read the refund row, checked
-- status = 'REQUESTED' in JS, then called the Razorpay Refund API. Two
-- concurrent Edge invocations (double-click "Initiate Refund", a client
-- retry) both passed that check and both called Razorpay → two real
-- refunds against one `refunds` row, and mark_refund_processing
-- (where status = 'REQUESTED') recorded only the first id.
--
-- After: the transition REQUESTED → PROCESSING is an atomic compare-and-set
-- in the database, taken BEFORE the Razorpay call. Exactly one caller wins
-- the claim and is allowed to talk to Razorpay; every other concurrent
-- caller gets NULL back and must not.
--
-- Reused as-is: request_refund / refundable_amount / the
-- refunds_one_active_per_order_idx partial unique index (0023) — those
-- already stop a second refund ROW; this stops a second Razorpay CALL for
-- the one row. mark_refund_failed (0023) already handles PROCESSING → FAILED
-- so the error path is unchanged. mark_refund_processing stays in place
-- (now unused by the submit path, no other callers) rather than being
-- dropped.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- claim_refund_for_submission: atomic REQUESTED → PROCESSING. Returns the
-- row to the single caller that performed the transition; returns a NULL
-- row (result.id is null) to everyone else — a lost race, or a refund that
-- was already past REQUESTED. A NULL return means "do NOT call Razorpay".
-- ─────────────────────────────────────────────────────────────────────────
create function claim_refund_for_submission(p_refund_id uuid) returns refunds
language plpgsql
as $$
declare
  result refunds;
begin
  update refunds
    set status = 'PROCESSING'
    where id = p_refund_id and status = 'REQUESTED'
    returning * into result;
  return result;
end;
$$;

grant execute on function claim_refund_for_submission(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- set_refund_razorpay_id: attach the Razorpay refund id after a successful
-- Refund API call. coalesce so a webhook that raced ahead and set it first
-- is never overwritten (same rule apply_refund_webhook's fallback relies
-- on).
-- ─────────────────────────────────────────────────────────────────────────
create function set_refund_razorpay_id(p_refund_id uuid, p_razorpay_refund_id text) returns refunds
language plpgsql
as $$
declare
  result refunds;
begin
  update refunds
    set razorpay_refund_id = coalesce(razorpay_refund_id, p_razorpay_refund_id)
    where id = p_refund_id
    returning * into result;
  if result.id is null then
    raise exception 'Refund not found.' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function set_refund_razorpay_id(uuid, text) to authenticated;
