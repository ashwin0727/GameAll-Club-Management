import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/payout_method.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../authentication/session_controller.dart';
import 'facility_sections.dart';
import 'hub_providers.dart';
import 'hub_widgets.dart';
import 'payout_widgets.dart';

/// Profile → Business → Payments & Payouts, and the hub's "Payment Methods": where the facility's money is paid out.
/// The owner can add, edit, remove and choose the primary bank account or UPI ID. GameAll verifies each by hand — a new
/// or edited method reads "Verification pending" until then.
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(payoutMethodsProvider);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String facilityId, {PayoutMethod? method}) async {
    if (await showPayoutMethodSheet(context, facilityId: facilityId, method: method)) {
      ref.invalidate(payoutMethodsProvider);
    }
  }

  Future<void> _confirmDelete(PayoutMethod m, bool onlyOne) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this payment method?'),
        content: Text(m.isPrimary && !onlyOne
            ? "This is where payouts currently go. Make another method primary afterwards so payouts aren't held up."
            : 'You can add it again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.tokens.destructive),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(payoutRepositoryProvider).delete(m.id), 'Could not remove this payment method.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final facility = ref.watch(sessionControllerProvider).facility;
    final owner = isFacilityOwner(ref);
    final methods = ref.watch(payoutMethodsProvider);

    return HubPage(
      title: 'Payments & Payouts',
      onRefresh: () async {
        ref.invalidate(payoutMethodsProvider);
        await ref.read(payoutMethodsProvider.future);
      },
      children: [
        Text('Where the money you collect for bookings and other payments is paid out to.',
            style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.4)),
        const SizedBox(height: AppSpacing.lg),
        if (facility == null)
          Text('No facility is set up for this account yet.', style: TextStyle(color: t.textSecondary))
        else if (!owner)
          HubCard(
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: t.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Payout details are managed by the facility owner.', style: TextStyle(color: t.textSecondary))),
              ],
            ),
          )
        else ...[
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: t.destructive.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: TextStyle(color: t.destructive, fontSize: 13)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          HubAsync<List<PayoutMethod>>(
            value: methods,
            onRetry: () => ref.invalidate(payoutMethodsProvider),
            builder: (list) => list.isEmpty
                ? HubCard(
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        IconBadge(icon: Icons.account_balance_outlined, color: t.primary, size: 52, round: true),
                        const SizedBox(height: AppSpacing.md),
                        Text('No payment method yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Add a bank account or UPI ID so we know where to pay out what you collect.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.4)),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: () => _open(facility.id),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add payment method'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (final m in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: PayoutMethodCard(
                            method: m,
                            busy: _busy,
                            onEdit: () => _open(facility.id, method: m),
                            onMakePrimary: () => _run(() => ref.read(payoutRepositoryProvider).setPrimary(m.id), 'Could not change the primary method.'),
                            onDelete: () => _confirmDelete(m, list.length == 1),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _open(facility.id),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add another'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_user_outlined, size: 15, color: t.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Account numbers are masked here and visible only to you. Payouts go to your primary method once it is verified.',
                              style: TextStyle(fontSize: 12, color: t.textSecondary, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}
