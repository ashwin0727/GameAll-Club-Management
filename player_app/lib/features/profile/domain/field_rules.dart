import 'package:flutter/services.dart';

/// The rules for every field on Personal Information: what may be typed (the [formatters]) and what is accepted on Save (the
/// validators, which return a sentence for the player, or null when the value is fine). The database repeats the same rules
/// (migration 0193), so a value that gets past a phone is still checked on the server.
class FieldRules {
  const FieldRules._();

  // ── limits ──────────────────────────────────────────────────────────────
  static const nameMin = 2;
  static const nameMax = 60;
  static const emailMax = 100;
  static const relationMax = 30;
  static const addressMax = 100;
  static const aboutMax = 200;
  static const mobileLength = 10;
  static const pinLength = 6;
  static const minBirthYear = 1920;

  // ── what may be typed ───────────────────────────────────────────────────
  static final _nameChars = RegExp(r"[\p{L}\p{M} .'\-]", unicode: true);
  static final _addressChars = RegExp(r"[\p{L}\p{M}\p{N} ,./#'&()\-]", unicode: true);

  /// Letters (any language), spaces, dot, apostrophe and hyphen: no digits or symbols.
  static List<TextInputFormatter> nameFormatters(int max) => [
    FilteringTextInputFormatter.allow(_nameChars),
    LengthLimitingTextInputFormatter(max),
  ];

  /// Digits only, at most ten.
  static List<TextInputFormatter> mobileFormatters() => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(mobileLength),
  ];

  static List<TextInputFormatter> pinFormatters() => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(pinLength),
  ];

  /// No spaces; the address is kept in lower case.
  static List<TextInputFormatter> emailFormatters() => [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
    LengthLimitingTextInputFormatter(emailMax),
  ];

  static List<TextInputFormatter> addressFormatters() => [
    FilteringTextInputFormatter.allow(_addressChars),
    LengthLimitingTextInputFormatter(addressMax),
  ];

  // ── what is accepted ────────────────────────────────────────────────────
  static final _nameShape = RegExp(r"^[\p{L}][\p{L}\p{M} .'\-]*$", unicode: true);
  static final _emailShape = RegExp(
    r"^[A-Za-z0-9._%+\-]+@(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
  );
  static final _mobileShape = RegExp(r'^[6-9][0-9]{9}$');
  static final _addressShape = RegExp(r"^[\p{L}\p{M}\p{N} ,./#'&()\-]+$", unicode: true);

  static String squash(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// A person's name ("Full Name", the emergency contact): 2 to 60 letters, spaces, . ' -
  static String? name(String raw, {String what = 'name', bool required = true}) {
    final v = squash(raw);
    if (v.isEmpty) return required ? 'Please enter your $what.' : null;
    if (v.length < nameMin) return 'The $what is too short (at least $nameMin letters).';
    if (v.length > nameMax) return 'The $what is too long (at most $nameMax characters).';
    if (!_nameShape.hasMatch(v)) {
      return 'The $what can only have letters, spaces, . \' and -.';
    }
    return null;
  }

  static String? email(String raw, {bool required = false}) {
    final v = raw.trim();
    if (v.isEmpty) return required ? 'Please enter your email address.' : null;
    if (v.length > emailMax) return 'The email address is too long (at most $emailMax characters).';
    if (v.contains('..') || v.startsWith('.') || v.contains('.@')) {
      return 'Please enter a valid email address.';
    }
    if (!_emailShape.hasMatch(v)) return 'Please enter a valid email address.';
    return null;
  }

  /// The last ten digits of a number typed with or without +91 / 0 / spaces / dashes (what the database stores).
  static String tenDigits(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return d.length > mobileLength ? d.substring(d.length - mobileLength) : d;
  }

  /// An Indian mobile number: ten digits starting with 6, 7, 8 or 9. [own] is the player's own number (the one signed in with):
  /// an alternate or emergency number must be somebody else's / a different line.
  static String? mobile(String raw, {bool required = false, String? own, String what = 'mobile number'}) {
    final v = raw.trim();
    if (v.isEmpty) return required ? 'Please enter the $what.' : null;
    final d = tenDigits(v);
    if (!_mobileShape.hasMatch(d) || v.replaceAll(RegExp(r'\D'), '').length < mobileLength) {
      return 'Enter a valid 10-digit $what (it starts with 6, 7, 8 or 9).';
    }
    if (own != null && own.isNotEmpty && tenDigits(own) == d) {
      return 'This is the number you signed in with. Please enter a different one.';
    }
    return null;
  }

  static String? relationship(String raw) {
    final v = squash(raw);
    if (v.isEmpty) return null;
    if (v.length < 2) return 'The relationship is too short.';
    if (v.length > relationMax) return 'The relationship is too long (at most $relationMax characters).';
    if (!_nameShape.hasMatch(v)) return 'The relationship can only have letters, spaces, . \' and -.';
    return null;
  }

  static String? addressLine(String raw, {bool required = false, String what = 'Address line'}) {
    final v = squash(raw);
    if (v.isEmpty) return required ? 'Please enter the $what.' : null;
    if (v.length < 3) return 'The $what is too short.';
    if (v.length > addressMax) return 'The $what is too long (at most $addressMax characters).';
    if (!_addressShape.hasMatch(v)) {
      return 'The $what can only have letters, numbers, spaces and , . / # \' & ( ) -';
    }
    return null;
  }

  /// Six digits, the first not 0.
  static String? pincode(String raw, {bool required = false}) {
    final v = raw.trim();
    if (v.isEmpty) return required ? 'Please enter the PIN code.' : null;
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(v)) return 'PIN code must be 6 digits.';
    return null;
  }

  static String? about(String raw) {
    if (raw.length > aboutMax) return 'Keep it under $aboutMax characters.';
    if (RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]').hasMatch(raw)) {
      return 'Please remove the special characters.';
    }
    return null;
  }

  /// Born in 1920 or later and not in the future.
  static String? dob(DateTime? v, {DateTime? today}) {
    if (v == null) return 'Please choose your date of birth.';
    final now = today ?? DateTime.now();
    if (v.isAfter(DateTime(now.year, now.month, now.day))) return 'The date of birth cannot be in the future.';
    if (v.year < minBirthYear) return 'Please choose a valid date of birth.';
    return null;
  }

  /// A photo or document file: its extension must be JPG, PNG or WEBP.
  static String? imageFile(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return null;
    }
    return 'Please choose a JPG, PNG or WEBP image.';
  }
}
