import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

/// What deleting the account did. The account is either gone, or only closed while online payments still waiting to be settled
/// to a venue are finished (everything else is then deleted by itself).
sealed class AccountDeletion {
  const AccountDeletion();
}

class AccountDeleted extends AccountDeletion {
  const AccountDeleted();
}

class AccountClosedForNow extends AccountDeletion {
  const AccountClosedForNow();
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Deleting the signed-in player's own account (the delete-account function). The server reads who it is from the sign-in: the app
/// never says whose account to delete. Tests supply a fake.
abstract class AccountRepository {
  Future<AccountDeletion> deleteMyAccount();
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<AccountDeletion> deleteMyAccount() async {
    const fallback =
        'We could not delete your account. Please try again or contact support.';
    final client = _client;
    if (client == null) throw const AccountDeletionException(fallback);
    try {
      final res = await client.functions.invoke(
        'delete-account',
        body: {'confirm': true},
      );
      final data = res.data;
      if (data is Map) {
        if (data['status'] == 'deleted') return const AccountDeleted();
        if (data['status'] == 'pending') return const AccountClosedForNow();
      }
    } on FunctionException catch (e) {
      final d = e.details;
      throw AccountDeletionException(
        d is Map ? (d['error'] as String? ?? fallback) : fallback,
      );
    }
    throw const AccountDeletionException(fallback);
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => SupabaseAccountRepository(),
);
