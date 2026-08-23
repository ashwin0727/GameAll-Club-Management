/// Pure form-validation functions — independently unit-testable, and kept
/// out of widgets so the same rule can't drift between screens.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _tenDigitPhone = RegExp(r'^\d{10}$');
  static final RegExp _sixDigitPin = RegExp(r'^\d{6}$');

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_email.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Confirm your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? name(String? value, {int minLength = 2}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required.';
    if (trimmed.length < minLength) {
      return 'Name must be at least $minLength characters.';
    }
    return null;
  }

  static String? phone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    if (!_tenDigitPhone.hasMatch(trimmed.replaceAll(RegExp(r'^\+91'), ''))) {
      return 'Enter a valid 10-digit phone number.';
    }
    return null;
  }

  static String? pinCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'PIN code is required.';
    if (!_sixDigitPin.hasMatch(trimmed)) return 'Enter a valid 6-digit PIN code.';
    return null;
  }

  static String? positiveAmount(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Amount is required.';
    final parsed = num.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid amount.';
    if (parsed <= 0) return 'Amount must be greater than 0.';
    return null;
  }
}