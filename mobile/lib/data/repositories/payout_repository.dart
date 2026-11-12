import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/payout_method.dart';
import '../models/payout_settings.dart';

/// Mirrors the web `SupabaseProfileService` payout methods: same table
/// (`facility_payout_methods`, migration 0148), so a method added on mobile
/// shows on web and vice versa. Verification is GameAll's — a new or edited
/// method always starts pending (the database enforces it).
/// Never `select()`: the account_number column is not readable by the signed-in owner (migration 0200).
const _payoutColumns =
    'id, facility_id, method_type, account_holder_name, bank_name, ifsc, upi_id, is_primary, verification_status, verified_at, verification_note, created_at, account_type, account_last4';

String _accountTypeValue(PayoutAccountType t) => t == PayoutAccountType.current ? 'CURRENT' : 'SAVINGS';

class PayoutRepository {
  PayoutRepository(this._client);

  final SupabaseClient _client;

  Future<List<PayoutMethod>> list(String facilityId) async {
    try {
      final rows = await _client
          .from('facility_payout_methods')
          .select(_payoutColumns)
          .eq('facility_id', facilityId)
          .order('is_primary', ascending: false)
          .order('created_at', ascending: true);
      return (rows as List<dynamic>)
          .map((r) => PayoutMethod.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The first method added becomes the primary one.
  Future<PayoutMethod> addBank(
    String facilityId, {
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String ifsc,
    PayoutAccountType accountType = PayoutAccountType.savings,
  }) =>
      _insert(facilityId, {
        'method_type': 'BANK',
        'account_holder_name': accountHolderName.trim(),
        'bank_name': bankName.trim(),
        'account_number': accountNumber.trim(),
        'ifsc': ifsc.trim().toUpperCase(),
        'account_type': _accountTypeValue(accountType),
      });

  Future<PayoutMethod> addUpi(
    String facilityId, {
    required String accountHolderName,
    required String upiId,
  }) =>
      _insert(facilityId, {
        'method_type': 'UPI',
        'account_holder_name': accountHolderName.trim(),
        'upi_id': upiId.trim().toLowerCase(),
      });

  Future<PayoutMethod> _insert(String facilityId, Map<String, dynamic> fields) async {
    try {
      final existing = await _client
          .from('facility_payout_methods')
          .select('id')
          .eq('facility_id', facilityId);
      final row = await _client
          .from('facility_payout_methods')
          .insert({
            'facility_id': facilityId,
            'is_primary': (existing as List<dynamic>).isEmpty,
            ...fields,
          })
          .select(_payoutColumns)
          .single();
      return PayoutMethod.fromJson(row);
    } on PostgrestException catch (e) {
      // Our own rules (migration 0200): no duplicates, at most five accounts. Their messages are written for people.
      if (e.code == '23505') throw AppException(AppErrorCode.databaseError, 'This account has already been added.');
      if (e.code == '23514' && e.message.contains('payout accounts')) throw AppException(AppErrorCode.databaseError, e.message);
      throw mapSupabaseError(e);
    }
  }

  /// Editing the account details sends the method back for verification (the database enforces it).
  Future<void> updateBank(
    String methodId, {
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String ifsc,
    PayoutAccountType accountType = PayoutAccountType.savings,
  }) =>
      _update(methodId, {
        'method_type': 'BANK',
        'account_holder_name': accountHolderName.trim(),
        'bank_name': bankName.trim(),
        'account_number': accountNumber.trim(),
        'ifsc': ifsc.trim().toUpperCase(),
        'account_type': _accountTypeValue(accountType),
        'upi_id': null,
      });

  Future<void> updateUpi(String methodId, {required String accountHolderName, required String upiId}) => _update(methodId, {
        'method_type': 'UPI',
        'account_holder_name': accountHolderName.trim(),
        'upi_id': upiId.trim().toLowerCase(),
        'bank_name': null,
        'account_number': null,
        'ifsc': null,
        'account_type': null,
      });

  Future<void> _update(String methodId, Map<String, dynamic> fields) async {
    try {
      await _client
          .from('facility_payout_methods')
          .update({...fields, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', methodId);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<PayoutSettings> loadSettings(String facilityId) async {
    try {
      final row = await _client.from('facility_payout_settings').select().eq('facility_id', facilityId).maybeSingle();
      return row == null ? const PayoutSettings() : PayoutSettings.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> saveSettings(String facilityId, PayoutSettings settings) async {
    final problem = settings.validate();
    if (problem != null) throw AppException(AppErrorCode.databaseError, problem);
    try {
      await _client.from('facility_payout_settings').upsert(settings.toRow(facilityId), onConflict: 'facility_id');
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// After GameAll sent the setup back: the owner fixes things and sends it again. Owner only (the database refuses anyone else).
  Future<void> resubmitForReview(String facilityId) async {
    try {
      await _client.rpc('resubmit_facility_for_review', params: {'p_facility_id': facilityId});
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The verdict as the database has it now (for the "under review" screen to poll).
  Future<({String status, String? note})?> reviewStatus(String facilityId) async {
    try {
      final data = await _client.rpc('my_facility_review', params: {'p_facility_id': facilityId});
      if (data is! Map) return null;
      return (status: (data['status'] as String?) ?? 'PENDING', note: data['note'] as String?);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> setPrimary(String methodId) async {
    try {
      await _client.rpc('set_primary_payout_method', params: {'p_method_id': methodId});
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> delete(String methodId) async {
    try {
      await _client.from('facility_payout_methods').delete().eq('id', methodId);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}
