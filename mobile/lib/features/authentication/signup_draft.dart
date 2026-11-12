/// What the person typed on Create Your Account, carried through the verification pages. It lives in the Create Account page, so
/// going Back from a verification page returns to the same, filled-in form, and a number that was already verified is remembered.
class SignupDraft {
  SignupDraft();

  String name = '';

  /// The 10-digit mobile number (no +91).
  String phone = '';
  String email = '';
  String password = '';

  String? _mobileProof;
  String? _proofPhone;
  DateTime? _proofAt;

  /// The server accepts a phone proof for 30 minutes; stop trusting ours a little earlier.
  static const _proofLife = Duration(minutes: 25);

  /// True while the number currently in [phone] was verified by OTP recently enough for the proof to still be accepted.
  bool get phoneVerified {
    final at = _proofAt;
    return _mobileProof != null && _proofPhone == phone && at != null && DateTime.now().difference(at) < _proofLife;
  }

  /// The signed proof to send with the account creation, when [phoneVerified].
  String? get mobileProof => phoneVerified ? _mobileProof : null;

  void markPhoneVerified(String proof) {
    _mobileProof = proof;
    _proofPhone = phone;
    _proofAt = DateTime.now();
  }

  /// "+91 98765 43210"
  String get phoneDisplay => phone.length == 10 ? '+91 ${phone.substring(0, 5)} ${phone.substring(5)}' : '+91 $phone';
}
