enum PayoutMethodType { bank, upi }

/// GameAll checks every payout method by hand before sending money to it.
enum PayoutVerification { pending, verified, rejected }

/// Where the facility's money is paid out — a bank account or a UPI ID
/// (`facility_payout_methods`, migration 0148).
class PayoutMethod {
  const PayoutMethod({
    required this.id,
    required this.type,
    required this.accountHolderName,
    this.bankName,
    this.accountNumber,
    this.ifsc,
    this.upiId,
    required this.isPrimary,
    required this.verification,
    this.verificationNote,
  });

  final String id;
  final PayoutMethodType type;
  final String accountHolderName;
  final String? bankName;
  final String? accountNumber;
  final String? ifsc;
  final String? upiId;
  final bool isPrimary;
  final PayoutVerification verification;

  /// Why a method was rejected, written by GameAll.
  final String? verificationNote;

  factory PayoutMethod.fromJson(Map<String, dynamic> json) => PayoutMethod(
        id: json['id'] as String,
        type: json['method_type'] == 'UPI' ? PayoutMethodType.upi : PayoutMethodType.bank,
        accountHolderName: json['account_holder_name'] as String,
        bankName: json['bank_name'] as String?,
        accountNumber: json['account_number'] as String?,
        ifsc: json['ifsc'] as String?,
        upiId: json['upi_id'] as String?,
        isPrimary: json['is_primary'] == true,
        verification: switch (json['verification_status']) {
          'VERIFIED' => PayoutVerification.verified,
          'REJECTED' => PayoutVerification.rejected,
          _ => PayoutVerification.pending,
        },
        verificationNote: json['verification_note'] as String?,
      );
}
