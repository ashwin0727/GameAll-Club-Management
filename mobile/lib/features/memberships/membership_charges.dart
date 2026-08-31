/// Pure charge math for the Create Membership page — kept out of the widget
/// so it stays independently testable and can't drift from the server-side
/// computation in `create_membership_full` (0028_membership_creation_form.sql):
///   gst_amount := round(fee * gst / 100.0);
///   total      := fee + gst_amount + reg;
library;

class MembershipCharges {
  const MembershipCharges({
    required this.subTotal,
    required this.gstAmount,
    required this.registration,
    required this.total,
  });

  final int subTotal;
  final int gstAmount;
  final int registration;
  final int total;
}

int _nonNegative(num? value) {
  if (value == null || !value.isFinite || value <= 0) return 0;
  return value.round();
}

/// [feeInr] / [registrationInr] are whole rupees; [gstPercent] a percentage
/// (e.g. 18 for 18%). Negative / non-finite / null inputs are clamped to 0,
/// matching the RPC's `greatest(coalesce(...), 0)` guards.
MembershipCharges computeMembershipCharges({
  required num? feeInr,
  required num? gstPercent,
  required num? registrationInr,
}) {
  final fee = _nonNegative(feeInr);
  final reg = _nonNegative(registrationInr);
  final gst = gstPercent == null || !gstPercent.isFinite || gstPercent <= 0 ? 0.0 : gstPercent.toDouble();
  final gstAmount = (fee * gst / 100.0).round();
  return MembershipCharges(
    subTotal: fee,
    gstAmount: gstAmount,
    registration: reg,
    total: fee + gstAmount + reg,
  );
}