/// Field rules for a payout method — the same as the web
/// (`src/features/profile/payout-validation.ts`).
class PayoutValidators {
  const PayoutValidators._();

  static String? holderName(String? v) {
    final t = v?.trim() ?? '';
    if (t.length < 2) return "Enter the account holder's name.";
    if (t.length > 80) return 'That name is too long.';
    return null;
  }

  static String? bankName(String? v) {
    final t = v?.trim() ?? '';
    if (t.length < 2) return "Enter the bank's name.";
    if (t.length > 80) return 'That name is too long.';
    return null;
  }

  static String? accountNumber(String? v) {
    if (!RegExp(r'^\d{9,18}$').hasMatch(v?.trim() ?? '')) {
      return 'Account numbers are 9 to 18 digits.';
    }
    return null;
  }

  static String? ifsc(String? v) {
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch((v ?? '').trim().toUpperCase())) {
      return 'Enter a valid IFSC, like HDFC0001234.';
    }
    return null;
  }

  static String? upiId(String? v) {
    if (!RegExp(r'^[a-z0-9.\-_]{2,256}@[a-z][a-z0-9]{1,63}$')
        .hasMatch((v ?? '').trim().toLowerCase())) {
      return 'Enter a valid UPI ID, like name@bank.';
    }
    return null;
  }

  /// "XXXXXX1234" — enough to recognise an account, never the whole number.
  static String maskAccountNumber(String? n) {
    if (n == null || n.isEmpty) return '';
    return n.length <= 4 ? n : '${'X' * (n.length - 4)}${n.substring(n.length - 4)}';
  }

  /// "ch••••@okhdfc" — the handle's first two characters and the bank.
  static String maskUpi(String? upi) {
    if (upi == null || upi.isEmpty) return '';
    final at = upi.indexOf('@');
    final handle = at < 0 ? upi : upi.substring(0, at);
    final bank = at < 0 ? '' : upi.substring(at);
    final head = handle.length >= 2 ? handle.substring(0, 2) : handle;
    final dots = handle.length - 2 < 2 ? 2 : handle.length - 2;
    return '$head${'•' * dots}$bank';
  }
}
