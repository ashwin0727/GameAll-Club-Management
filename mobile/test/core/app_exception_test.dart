import 'package:flutter_test/flutter_test.dart';
import 'package:postgrest/postgrest.dart';
import 'package:gameall_club_mobile/core/errors/app_exception.dart';

PostgrestException _pgError(String code) =>
    PostgrestException(message: 'raw db detail', code: code);

void main() {
  group('mapSupabaseError', () {
    test('maps a unique-violation to the caller-supplied duplicate code', () {
      final result = mapSupabaseError(
        _pgError('23505'),
        duplicate: AppErrorCode.duplicatePlayingArea,
      );
      expect(result.code, AppErrorCode.duplicatePlayingArea);
    });

    test('maps a foreign-key violation to the caller-supplied not-found code', () {
      final result = mapSupabaseError(
        _pgError('23503'),
        notFound: AppErrorCode.facilitySportNotFound,
      );
      expect(result.code, AppErrorCode.facilitySportNotFound);
    });

    test('maps an RLS-blocked write to unauthorized regardless of context', () {
      final result = mapSupabaseError(_pgError('42501'));
      expect(result.code, AppErrorCode.unauthorized);
    });

    test('falls back to a generic database error for an unmapped code', () {
      final result = mapSupabaseError(_pgError('99999'));
      expect(result.code, AppErrorCode.databaseError);
    });

    test('never leaks the raw database message into the friendly message', () {
      final result = mapSupabaseError(_pgError('99999'));
      expect(result.message.contains('raw db detail'), isFalse);
    });

    test('passes an already-mapped AppException through unchanged', () {
      final original = AppException(AppErrorCode.facilityNotFound);
      expect(mapSupabaseError(original), same(original));
    });
  });
}