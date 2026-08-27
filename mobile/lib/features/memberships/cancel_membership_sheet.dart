import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/refund.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Membership cancellation — spec §14/§15: deliberately NOT policy/time-
/// driven. The owner explicitly decides the refund amount (full, partial, or
/// none) rather than it being computed automatically, since an active
/// membership isn't tied to a single future start time the way a booking is.
/// Mirrors `cancel-membership-dialog.tsx`. Pops `true` once the membership is
/// cancelled (whether or not a refund note is still showing) so the caller
/// always refreshes.
class CancelMembershipSheet extends ConsumerStatefulWidget {
  const CancelMembershipSheet({super.key, required this.membershipId, required this.planName});

  final String membershipId;
  final String planName;

  @override
  ConsumerState<CancelMembershipSheet> createState() => _CancelMembershipSheetState();
}

class _CancelMembershipSheetState extends ConsumerState<CancelMembershipSheet> {
  final _refundAmountController = TextEditingController();
  bool _isWorking = false;
  String? _error;
  String? _refundNote;

  @override
  void dispose() {
    _refundAmountController.dispose();
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    setState(() {
      _isWorking = true;
      _error = null;
      _refundNote = null;
    });
    try {
      final raw = _refundAmountController.text.trim();
      final amountInr = double.tryParse(raw);
      final refundAmountMinor = raw.isNotEmpty && amountInr != null && amountInr > 0 ? (amountInr * 100).round() : null;
      final result = await ref.read(refundRepositoryProvider).cancelMembership(
        CancelMembershipInput(
          membershipId: widget.membershipId,
          reason: 'Owner Request',
          refundAmountMinor: refundAmountMinor,
          overrideReason: refundAmountMinor != null ? 'Owner-decided membership cancellation refund' : null,
        ),
      );
      final refund = result.refund;
      if (refund != null && mounted) {
        setState(() {
          _refundNote = refund.status == RefundStatus.failed
              ? 'The membership was cancelled, but the refund could not be submitted. Please retry from Refunds.'
              : 'Refund submitted — it will show as processed once Razorpay confirms it.';
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cancel Membership', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(widget.planName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _refundAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Refund amount (optional)', prefixText: '₹ '),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Leave blank for no refund. The server enforces the maximum refundable amount.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_refundNote != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_refundNote!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isWorking ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Confirm Cancellation',
                    loadingLabel: 'Cancelling…',
                    isLoading: _isWorking,
                    onPressed: _confirmCancel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}