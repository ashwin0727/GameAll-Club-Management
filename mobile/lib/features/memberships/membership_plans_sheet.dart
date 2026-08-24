import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';

/// Facility-scoped membership plan management — plans are never
/// hard-coded, each facility manages its own list. Mirrors
/// `membership-plans-dialog.tsx`.
class MembershipPlansSheet extends ConsumerStatefulWidget {
  const MembershipPlansSheet({super.key, required this.facilityId});

  final String facilityId;

  @override
  ConsumerState<MembershipPlansSheet> createState() => _MembershipPlansSheetState();
}

class _MembershipPlansSheetState extends ConsumerState<MembershipPlansSheet> {
  List<MembershipPlan>? _plans;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _durationController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final plans = await ref.read(membershipRepositoryProvider).getFacilityPlans(widget.facilityId);
      if (mounted) setState(() => _plans = plans);
    } on AppException catch (_) {
      if (mounted) setState(() => _plans = []);
    }
  }

  Future<void> _addPlan() async {
    final name = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    if (name.length < 2) {
      setState(() => _error = 'Enter a plan name.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (duration == null || duration <= 0) {
      setState(() => _error = 'Enter a valid duration in days.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref
          .read(membershipRepositoryProvider)
          .createPlan(MembershipPlanInput(facilityId: widget.facilityId, name: name, priceInr: price, durationDays: duration));
      _nameController.clear();
      _priceController.clear();
      _durationController.clear();
      await _reload();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleActive(MembershipPlan plan) async {
    try {
      await ref.read(membershipRepositoryProvider).updatePlan(plan.id, isActive: !plan.isActive);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Membership Plans', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Manage the plans members can be assigned at this facility.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_plans == null)
                  const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
                else ...[
                  if (_plans!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('No plans yet — add the first one below.'),
                    )
                  else
                    ..._plans!.map(
                      (plan) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(plan.name, style: Theme.of(context).textTheme.titleSmall),
                                    Text(
                                      '${Formatters.currencyInr(plan.priceInr)} · ${plan.durationDays} days',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => _toggleActive(plan),
                                child: Text(plan.isActive ? 'Deactivate' : 'Activate'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Add a plan', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Plan name', hintText: 'e.g. Monthly, Quarterly, Annual'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          decoration: const InputDecoration(labelText: 'Price (₹)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _durationController,
                          decoration: const InputDecoration(labelText: 'Duration (days)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(onPressed: _isSaving ? null : _addPlan, child: Text(_isSaving ? 'Saving…' : 'Add Plan')),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}