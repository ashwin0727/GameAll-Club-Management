import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import 'coaching_common.dart';

/// The Razorpay payment link (one-time program) or AutoPay subscription (monthly program) behind a
/// coaching enrollment — its status, the shareable link, and the controls to start or stop it.
/// Mirrors src/features/coaching/components/enrollment-billing-card.tsx.
///
/// The money itself is recorded by the Razorpay webhook as ordinary payments, so the payments list
/// beneath this card stays the single source of truth for what has been collected.
class CoachingBillingCard extends ConsumerStatefulWidget {
  const CoachingBillingCard({
    super.key,
    required this.enrollmentId,
    required this.outstandingMinor,
    required this.canManage,
    required this.onChanged,
  });

  final String enrollmentId;
  final int outstandingMinor;
  final bool canManage;

  /// Called after a link is created or cancelled so the parent screen can refresh.
  final VoidCallback onChanged;

  @override
  ConsumerState<CoachingBillingCard> createState() => _CoachingBillingCardState();
}

class _CoachingBillingCardState extends ConsumerState<CoachingBillingCard> with WidgetsBindingObserver {
  EnrollmentBilling? _billing;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      _startPolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  // Back from the Razorpay page / another app → check straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  /// While a link / mandate is live, keep asking Razorpay so the card flips to Paid the moment the
  /// student finishes. The webhook records the same payment idempotently — whichever lands first wins.
  void _startPolling() {
    _poll?.cancel();
    if (_billing?.isLive != true) return;
    _check();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking || !mounted || _billing?.isLive != true) return;
    _checking = true;
    final repo = ref.read(coachingRepositoryProvider);
    try {
      try {
        await repo.reconcileEnrollmentBilling(widget.enrollmentId);
      } on AppException {
        // Razorpay unreachable / function not deployed — the webhook or the next tick catches up.
      }
      final fresh = await repo.getEnrollmentBilling(widget.enrollmentId);
      if (!mounted) return;
      final before = _billing;
      final changed = fresh?.status != before?.status || fresh?.chargeCount != before?.chargeCount;
      setState(() => _billing = fresh);
      if (changed) widget.onChanged();
      if (fresh?.isLive != true) _poll?.cancel();
    } on AppException {
      // transient — next tick retries
    } finally {
      _checking = false;
    }
  }

  @override
  void didUpdateWidget(CoachingBillingCard old) {
    super.didUpdateWidget(old);
    // A payment landing changes what is outstanding — pick up the new link status with it.
    if (old.outstandingMinor != widget.outstandingMinor) _load();
  }

  Future<void> _load() async {
    try {
      final b = await ref.read(coachingRepositoryProvider).getEnrollmentBilling(widget.enrollmentId);
      if (mounted) {
        setState(() {
          _billing = b;
          _loaded = true;
        });
      }
    } on AppException {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
      _startPolling();
      widget.onChanged();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel(EnrollmentBilling b) async {
    final what = b.isSubscription ? 'monthly auto-pay' : 'this payment link';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel $what?'),
        content: const Text('The student will no longer be able to pay through it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel it')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(coachingRepositoryProvider).cancelEnrollmentBilling(widget.enrollmentId));
    }
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final b = _billing;
    // Nothing to show: no online billing and nothing left to collect (or no right to start one).
    if (b == null && (!widget.canManage || widget.outstandingMinor <= 0)) return const SizedBox.shrink();

    final repo = ref.read(coachingRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text('Online Payment', style: AppTypography.rowTitle(context))),
                if (b != null)
                  StatusBadge(
                    label: b.statusLabel,
                    tone: switch (b.status) {
                      'PAID' || 'ACTIVE' || 'COMPLETED' => StatusTone.success,
                      'HALTED' => StatusTone.danger,
                      'CANCELLED' || 'EXPIRED' => StatusTone.neutral,
                      _ => StatusTone.warning,
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (b != null) ...[
              Text(
                b.isSubscription
                    ? 'Monthly auto-pay · ${coachMoney(b.amountMinor)} per month · ${b.chargeCount} of ${b.totalCycles} charged'
                        '${b.currentEnd != null ? ' · next cycle ends ${coachDate(b.currentEnd)}' : ''}'
                    : 'Payment link · ${coachMoney(b.amountMinor)}',
                style: AppTypography.secondary(context),
              ),
              if (b.isLive && b.shortUrl != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: SelectableText(b.shortUrl!, style: AppTypography.caption(context))),
                    TextButton.icon(
                      onPressed: () => _copy(b.shortUrl!),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
              if (b.status == 'HALTED')
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Razorpay stopped retrying a failed charge. Ask the student to update their payment method from the link.',
                    style: TextStyle(fontSize: 12, color: context.tokens.destructive),
                  ),
                ),
              if (widget.canManage && b.isLive)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _confirmCancel(b),
                    child: Text(b.isSubscription ? 'Cancel auto-pay' : 'Cancel link'),
                  ),
                ),
              if (widget.canManage && !b.isLive && b.status != 'PAID' && b.status != 'COMPLETED' && widget.outstandingMinor > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: FilledButton(
                    onPressed: _busy ? null : () => _run(() => repo.createEnrollmentBilling(widget.enrollmentId)),
                    child: const Text('Generate a new link'),
                  ),
                ),
            ] else ...[
              Text(
                'Collect ${coachMoney(widget.outstandingMinor)} online. Sends a Razorpay payment link — or, for a monthly '
                'program, sets up monthly auto-pay.',
                style: AppTypography.secondary(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _busy ? null : () => _run(() => repo.createEnrollmentBilling(widget.enrollmentId)),
                  child: Text(_busy ? 'Generating…' : 'Collect online'),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: context.tokens.destructive)),
              ),
          ],
        ),
      ),
    );
  }
}
