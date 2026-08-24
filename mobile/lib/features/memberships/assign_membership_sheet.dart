import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
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
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Confirm',
                loadingLabel: 'Saving…',
                isLoading: _isSaving,
                onPressed: _planId == null ? null : _confirm,
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