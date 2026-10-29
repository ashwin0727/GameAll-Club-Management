import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';

/// What happened when the person asked to delete their account.
sealed class AccountDeletionResult {
  const AccountDeletionResult();
}

/// Everything was deleted.
class AccountDeleted extends AccountDeletionResult {
  const AccountDeleted();
}

/// Online payments are still waiting to be settled: the account is closed and its records kept until they are, then it is deleted
/// automatically.
class AccountClosedPendingSettlement extends AccountDeletionResult {
  const AccountClosedPendingSettlement({required this.unsettledCount, required this.unsettledInr});
  final int unsettledCount;
  final int unsettledInr;
}

/// Deleting the signed-in person's own account (delete-account edge function). The person is identified by their sign-in on the
/// server; nothing here says whose account to delete.
class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  Future<AccountDeletionResult> deleteMyAccount() async {
    const fallback = 'We could not delete your account. Please try again or contact support.';
    try {
      final res = await _client.functions.invoke('delete-account', body: {'confirm': true});
      final data = res.data;
      if (data is Map) {
        if (data['status'] == 'deleted') return const AccountDeleted();
        if (data['status'] == 'pending') {
          return AccountClosedPendingSettlement(
            unsettledCount: (data['unsettledCount'] as num?)?.toInt() ?? 0,
            unsettledInr: (data['unsettledInr'] as num?)?.round() ?? 0,
          );
        }
      }
    } on FunctionException catch (e) {
      final d = e.details;
      throw AppException(AppErrorCode.databaseError, d is Map ? (d['error'] as String? ?? fallback) : fallback);
    }
    throw AppException(AppErrorCode.databaseError, fallback);
  }
}
