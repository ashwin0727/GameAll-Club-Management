import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/errors/app_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a refused court removal reaches the owner with its own explanation', () {
    final e = mapSupabaseError(
      const PostgrestException(
        message: 'Court 3 has 2 upcoming bookings — move or cancel them before removing or switching it off.',
        code: '23514',
      ),
    );
    expect(e.message, contains('2 upcoming bookings'));
  });

  test('other constraint failures stay generic', () {
    final e = mapSupabaseError(const PostgrestException(message: 'some other check failed', code: '23514'));
    expect(e.message, isNot(contains('some other check failed')));
  });
}
