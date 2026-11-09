import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/features/profile/domain/field_rules.dart';

String _typed(List<TextInputFormatter> f, String text) {
  var v = const TextEditingValue();
  for (final ch in text.split('')) {
    var next = TextEditingValue(
      text: v.text + ch,
      selection: TextSelection.collapsed(offset: v.text.length + 1),
    );
    for (final x in f) {
      next = x.formatEditUpdate(v, next);
    }
    v = next;
  }
  return v.text;
}

void main() {
  group('names', () {
    test('accept normal names', () {
      for (final n in ["Uma Shankar M", "Anne-Marie O'Neil", 'J. R. Smith', 'அருண்', 'Zoë']) {
        expect(FieldRules.name(n), isNull, reason: n);
      }
    });
    test('refuse empty, one letter, digits, symbols and too long', () {
      expect(FieldRules.name('  '), 'Please enter your name.');
      expect(FieldRules.name('A'), contains('too short'));
      expect(FieldRules.name('Uma 2'), contains('can only have letters'));
      expect(FieldRules.name('Uma@home'), contains('can only have letters'));
      expect(FieldRules.name('-Uma'), contains('can only have letters'));
      expect(FieldRules.name('A' * 61), contains('too long'));
    });
    test('an optional name may be empty', () {
      expect(FieldRules.name('', required: false), isNull);
    });
    test('typing drops digits and symbols and stops at the limit', () {
      expect(_typed(FieldRules.nameFormatters(10), 'Uma 12@#Sh'), 'Uma Sh');
      expect(_typed(FieldRules.nameFormatters(5), 'Shankar'), 'Shank');
    });
  });

  group('email', () {
    test('accepts valid addresses', () {
      for (final e in ['uma@gmail.com', 'a.b+c@sub.example.co.in', 'x_y-z@host.io']) {
        expect(FieldRules.email(e), isNull, reason: e);
      }
    });
    test('refuses bad ones', () {
      for (final e in ['nope', 'a@b', 'a@b.c', '@x.com', 'a b@x.com', 'a..b@x.com', '.a@x.com', 'a.@x.com', 'a@-x.com', 'a@x..com']) {
        expect(FieldRules.email(e), isNotNull, reason: e);
      }
      expect(FieldRules.email('${'a' * 95}@x.com'), contains('too long'));
    });
    test('empty is fine unless required', () {
      expect(FieldRules.email(''), isNull);
      expect(FieldRules.email('', required: true), isNotNull);
    });
    test('typing never takes a space', () {
      expect(_typed(FieldRules.emailFormatters(), 'a b@x .com'), 'ab@x.com');
    });
  });

  group('mobile numbers', () {
    test('accept ten digits starting 6-9, with or without +91', () {
      for (final n in ['9876543210', '6000000000', '+91 98765 43210', '09876543210', '91-9876543210']) {
        expect(FieldRules.mobile(n), isNull, reason: n);
      }
    });
    test('refuse short, long, letters and bad first digit', () {
      for (final n in ['12345', '5876543210', '98765432101234', '98765abcde', '98765 4321']) {
        expect(FieldRules.mobile(n), isNotNull, reason: n);
      }
    });
    test('must differ from the signed-in number', () {
      expect(FieldRules.mobile('9876543210', own: '+91 9876543210'), contains('different'));
      expect(FieldRules.mobile('9876543211', own: '9876543210'), isNull);
    });
    test('typing takes digits only, ten at most', () {
      expect(_typed(FieldRules.mobileFormatters(), '98a76-54 3210999'), '9876543210');
    });
    test('tenDigits keeps the last ten', () {
      expect(FieldRules.tenDigits('+91 98765-43210'), '9876543210');
    });
  });

  group('address', () {
    test('PIN: six digits, not starting with 0', () {
      expect(FieldRules.pincode('600020'), isNull);
      for (final p in ['60002', '6000200', '060020', 'abcdef']) {
        expect(FieldRules.pincode(p), 'PIN code must be 6 digits.', reason: p);
      }
      expect(_typed(FieldRules.pinFormatters(), '6a00-0209'), '600020');
    });
    test('address lines', () {
      expect(FieldRules.addressLine('12/B, Lake Road (near park) #3'), isNull);
      expect(FieldRules.addressLine('ab'), contains('too short'));
      expect(FieldRules.addressLine('x' * 101), contains('too long'));
      expect(FieldRules.addressLine('Lake <Road>'), contains('can only have'));
      expect(FieldRules.addressLine('', required: true), isNotNull);
      expect(FieldRules.addressLine(''), isNull);
    });
    test('relationship', () {
      expect(FieldRules.relationship('Father'), isNull);
      expect(FieldRules.relationship(''), isNull);
      expect(FieldRules.relationship('Dad2'), isNotNull);
      expect(FieldRules.relationship('x' * 31), isNotNull);
    });
  });

  group('the rest', () {
    test('date of birth', () {
      final today = DateTime(2026, 11, 9);
      expect(FieldRules.dob(DateTime(2001, 9, 15), today: today), isNull);
      expect(FieldRules.dob(null), isNotNull);
      expect(FieldRules.dob(DateTime(2027, 1, 1), today: today), contains('future'));
      expect(FieldRules.dob(DateTime(1900, 1, 1), today: today), contains('valid'));
    });
    test('about you', () {
      expect(FieldRules.about('Looking for games'), isNull);
      expect(FieldRules.about('x' * 201), isNotNull);
      expect(FieldRules.about('bad\u0000text'), isNotNull);
    });
    test('image files', () {
      expect(FieldRules.imageFile('JPG'), isNull);
      expect(FieldRules.imageFile('webp'), isNull);
      expect(FieldRules.imageFile('gif'), isNotNull);
      expect(FieldRules.imageFile('pdf'), isNotNull);
    });
  });
}
