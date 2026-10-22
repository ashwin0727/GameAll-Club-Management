import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/payout_method.dart';

/// Mirrors the web `SupabaseProfileService` payout methods: same table
/// (`facility_payout_methods`, migration 0148), so a method added on mobile
/// shows on web and vice versa. Verification is GameAll's — a new or edited
/// method always starts pending (the database enforces it).
class PayoutRepository {
  PayoutRepository(this._client);

  final SupabaseClient _client;

  Future<List<PayoutMethod>> list(String facilityId) async {
    try {
      final rows = await _client
          .from('facility_payout_methods')
          .select()
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
  }) =>
      _insert(facilityId, {
        'method_type': 'BANK',
        'account_holder_name': accountHolderName.trim(),
        'bank_name': bankName.trim(),
        'account_number': accountNumber.trim(),
        'ifsc': ifsc.trim().toUpperCase(),
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
          .select()
          .single();
      return PayoutMethod.fromJson(row);
    } on PostgrestException catch (e) {
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
  }) =>
      _update(methodId, {
        'method_type': 'BANK',
        'account_holder_name': accountHolderName.trim(),
        'bank_name': bankName.trim(),
        'account_number': accountNumber.trim(),
        'ifsc': ifsc.trim().toUpperCase(),
        'upi_id': null,
      });

  Future<void> updateUpi(String methodId, {required String accountHolderName, required String upiId}) => _update(methodId, {
        'method_type': 'UPI',
        'account_holder_name': accountHolderName.trim(),
        'upi_id': upiId.trim().toLowerCase(),
        'bank_name': null,
        'account_number': null,
        'ifsc': null,
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
