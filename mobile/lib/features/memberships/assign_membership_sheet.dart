import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';
import 'membership_status.dart';

/// Assign a plan to a member, or renew (same write path — a new start date
/// always inserts a new membership row, never overwrites history). Mirrors
/// `assign-membership-dialog.tsx`. Returns the created [Membership] via
/// `Navigator.pop`, or null if dismissed.
class AssignMembershipSheet extends ConsumerStatefulWidget {
  const AssignMembershipSheet({super.key, required this.facilityId, required this.memberId, required this.memberName});

  final String facilityId;
  final String memberId;
  final String memberName;

  @override
  ConsumerState<AssignMembershipSheet> createState() => _AssignMembershipSheetState();
}

class _AssignMembershipSheetState extends ConsumerState<AssignMembershipSheet> {
  List<MembershipPlan>? _plans;
  String? _planId;
  DateTime _startDate = DateTime.now();
  bool _paymentPaid = true;
  bool _isSaving = false;
  bool _isPayingViaRazorpay = false;
  bool _isCheckingAgain = false;
  CheckoutResult? _paymentState;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await ref.read(membershipRepositoryProvider).getFacilityPlans(widget.facilityId, activeOnly: true);
      if (mounted) setState(() => _plans = plans);
    } on AppException catch (_) {
      if (mounted) setState(() => _plans = []);
    }
  }

  MembershipPlan? get _selectedPlan => _plans?.where((p) => p.id == _planId).firstOrNull;

  DateTime? get _endDate {
    final plan = _selectedPlan;
    if (plan == null) return null;
    return computeMembershipEndDate(_startDate, plan.durationDays);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _confirm() async {
    final plan = _selectedPlan;
    if (plan == null) {
      setState(() => _error = 'Select a membership plan.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final membership = await ref
          .read(membershipRepositoryProvider)
          .createMembership(
            CreateMembershipInput(
              memberId: widget.memberId,
              facilityId: widget.facilityId,
              planId: plan.id,
              startDate: _startDate,
              paymentStatus: _paymentPaid ? 'paid' : 'created',
            ),
          );
      if (mounted) Navigator.of(context).pop(membership);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Alternative to the manual Paid/Pending toggle: pay through the
  /// Razorpay checkout. Mirrors the now-FIXED `payWithRazorpay` in
  /// assign-membership-dialog.tsx — a "captured" result here is a VERIFIED
  /// payment, but membership activation is deliberately NOT performed by
  /// this payment phase (spec §"Membership Payment": "DO NOT activate the
  /// Membership yet — membership activation belongs to the next business
  /// settlement phase"). This only flips the existing manual "Paid" toggle
  /// to true and shows the payment status panel; staff still has to press
  /// the existing "Confirm" button below to actually assign the membership.
  Future<void> _payViaRazorpay() async {
    final plan = _selectedPlan;
    if (plan == null) {
      setState(() => _error = 'Select a membership plan.');
      return;
    }
    setState(() {
      _isPayingViaRazorpay = true;
      _error = null;
      _paymentState = null;
    });
    try {
      final result = await ref.read(paymentCheckoutControllerProvider).startCheckout(
        CreatePaymentOrderInput(
          facilityId: widget.facilityId,
          sourceType: PaymentSourceType.membership,
          memberId: widget.memberId,
          planId: plan.id,
        ),
        contactName: widget.memberName,
      );
      if (!mounted) return;
      setState(() => _paymentState = result is CheckoutCancelled ? null : result);
      if (result is CheckoutCaptured) {
        setState(() => _paymentPaid = true);
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isPayingViaRazorpay = false);
    }
  }

  Future<void> _handleCheckAgain(String paymentOrderId) async {
    setState(() => _isCheckingAgain = true);
    try {
      final result = await ref.read(paymentCheckoutControllerProvider).checkAgain(paymentOrderId);
      if (!mounted) return;
      setState(() => _paymentState = result);
      if (result is CheckoutCaptured) {
        setState(() => _paymentPaid = true);
      }
    } finally {
      if (mounted) setState(() => _isCheckingAgain = false);
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
            Text('Assign Membership', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(widget.memberName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            if (_plans == null)
              const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
            else if (_plans!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('No membership plans have been set up for this facility yet. Add a plan first.'),
              )
            else ...[
              Text('Plan', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ..._plans!.map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _planId = plan.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _planId == plan.id ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                          width: _planId == plan.id ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text('${plan.name} · ${plan.durationDays} days')),
                          Text(Formatters.currencyInr(plan.priceInr), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Start date', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: _pickStartDate, child: Text(Formatters.dateShort(_startDate))),
              if (_endDate != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Ends ${Formatters.dateShort(_endDate!)} · ${Formatters.currencyInr(_selectedPlan!.priceInr)}'),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text('Payment', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ChoiceChip(label: const Text('Paid'), selected: _paymentPaid, onSelected: (_) => setState(() => _paymentPaid = true)),
                  const SizedBox(width: AppSpacing.sm),
                  ChoiceChip(label: const Text('Pending'), selected: !_paymentPaid, onSelected: (_) => setState(() => _paymentPaid = false)),
                ],
              ),
              if (_paymentState != null || _isPayingViaRazorpay) ...[
                const SizedBox(height: AppSpacing.sm),
                PaymentStatusPanel(
                  state: _paymentState,
                  isProcessing: _isPayingViaRazorpay,
                  isCheckingAgain: _isCheckingAgain,
                  onCheckAgain: _paymentState is CheckoutPending
                      ? () => _handleCheckAgain((_paymentState as CheckoutPending).paymentOrderId)
                      : null,
                  onRetry: _paymentState is CheckoutFailed ? _payViaRazorpay : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Confirm',
                loadingLabel: 'Saving…',
                isLoading: _isSaving,
                onPressed: _planId == null || _isPayingViaRazorpay ? null : _confirm,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: _isPayingViaRazorpay ? 'Paying…' : 'Pay via Razorpay',
                onPressed: _planId == null || _isSaving || _isPayingViaRazorpay ? null : _payViaRazorpay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}