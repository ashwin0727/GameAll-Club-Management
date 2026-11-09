import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../payments/application/payment_flow.dart';
import '../../../payments/domain/payment_receipt.dart';
import '../../application/player_home_controller.dart';
import '../../domain/player_dashboard_models.dart';
import 'payment_reminder.dart';

/// "Complete your payment" prompts at the top of Home: one per membership, coaching enrolment or booking that is not fully paid.
/// A failed or late payment is shown in red and spoken about more firmly; each has a button that opens the Razorpay page right here.
/// Coming back from that page reloads Home, so a prompt disappears by itself once the payment has gone through.
class PaymentPrompts extends ConsumerStatefulWidget {
  const PaymentPrompts({
    super.key,
    required this.payments,
    this.onNavigate,
    this.popup = false,
    this.reminderEvery = const Duration(minutes: 5),
  });

  final List<PendingPayment> payments;

  /// Phone: no inline cards. A warning popup (with arrows when there are several) opens when Home opens and again every
  /// [reminderEvery] while something is unpaid; a slim banner on Home reopens it.
  final bool popup;
  final Duration reminderEvery;

  /// When the popup was last shown. Static, so Home being rebuilt does not reset the gap; a fresh app start does.
  static DateTime? _lastShown;

  /// Test hook: forget the last reminder (as after a fresh app start).
  static void resetReminder() {
    _lastShown = null;
    clock = DateTime.now;
  }

  /// The time source (replaced in tests).
  static DateTime Function() clock = DateTime.now;

  /// Opens a route from the "Payment Successful" page's buttons.
  final void Function(String route)? onNavigate;

  @override
  ConsumerState<PaymentPrompts> createState() => _PaymentPromptsState();
}

class _PaymentPromptsState extends ConsumerState<PaymentPrompts>
    with WidgetsBindingObserver {
  String? _busy;
  Timer? _timer;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.popup) {
      _timer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _maybeRemind(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRemind());
    }
  }

  @override
  void didUpdateWidget(PaymentPrompts old) {
    super.didUpdateWidget(old);
    if (widget.popup && old.payments.isEmpty && widget.payments.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRemind());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the payment page (or the browser tab): look again at what is paid, and remind if the gap has passed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playerHomeProvider.notifier).refresh();
      if (widget.popup) _maybeRemind();
    }
  }

  /// Opens the popup when something is unpaid, no popup is open, Home is the page in front and the gap has passed.
  void _maybeRemind({bool force = false}) {
    if (!mounted || !widget.popup || _dialogOpen || _busy != null) return;
    if (widget.payments.isEmpty) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final last = PaymentPrompts._lastShown;
    if (!force &&
        last != null &&
        PaymentPrompts.clock().difference(last) < widget.reminderEvery) {
      return;
    }
    PaymentPrompts._lastShown = PaymentPrompts.clock();
    _dialogOpen = true;
    showDialog<PendingPayment>(
      context: context,
      builder: (_) => PaymentReminderDialog(payments: widget.payments),
    ).then((chosen) {
      _dialogOpen = false;
      // the reminder gap counts from when it was closed
      PaymentPrompts._lastShown = PaymentPrompts.clock();
      if (chosen != null && mounted) _pay(chosen);
    });
  }

  Future<void> _pay(PendingPayment p) async {
    final key = '${p.kind.name}-${p.id}';
    setState(() => _busy = key);
    try {
      await openPaymentFlow(
        context,
        onNavigate: widget.onNavigate ?? (_) {},
        job: PaymentJob(
          kind: switch (p.kind) {
            PendingPaymentKind.membership => PaymentKind.membership,
            PendingPaymentKind.coaching => PaymentKind.coaching,
            _ => PaymentKind.booking,
          },
          title: p.title,
          venueName: p.venueName,
          balance: p.isBalance,
          prepare: () async => PaymentTarget(
            id: p.id,
            link: await ref
                .read(pendingPaymentRepositoryProvider)
                .paymentLink(p),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        ref.read(playerHomeProvider.notifier).refresh();
      }
    }
  }

  final _synced = <String>{};

  /// Razorpay may have taken a payment while our webhook was late: ask once per item, and reload Home if any turn out paid.
  void _syncPending() {
    final todo = [
      for (final p in widget.payments)
        if (p.kind != PendingPaymentKind.booking &&
            _synced.add('${p.kind.name}-${p.id}'))
          p,
    ];
    if (todo.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var changed = false;
      for (final p in todo) {
        final r = await ref
            .read(paymentReceiptRepositoryProvider)
            .sync(
              p.kind == PendingPaymentKind.membership
                  ? PaymentKind.membership
                  : PaymentKind.coaching,
              p.id,
            )
            .catchError((_) => null);
        if (r != null && r.isPaid) changed = true;
      }
      if (mounted && changed) ref.read(playerHomeProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.payments.isEmpty) return const SizedBox.shrink();
    _syncPending();
    if (widget.popup) {
      return ReminderBanner(
        payments: widget.payments,
        onTap: () => _maybeRemind(force: true),
      );
    }
    return Column(
      key: const ValueKey('payment-prompts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in widget.payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PromptCard(
              payment: p,
              busy: _busy == '${p.kind.name}-${p.id}',
              onPay: _busy == null ? () => _pay(p) : null,
            ),
          ),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.payment,
    required this.busy,
    required this.onPay,
  });

  final PendingPayment payment;
  final bool busy;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final copy = paymentPromptCopy(payment);
    final tint = payment.urgent ? AppColors.danger : AppColors.warning;
    final icon = payment.urgent
        ? Icons.error_outline_rounded
        : Icons.schedule_rounded;
    final radius = BorderRadius.circular(AppDimensions.cardRadius);

    final button = Semantics(
      button: true,
      enabled: onPay != null,
      label: copy.button,
      child: ExcludeSemantics(
        child: Pressable(
          key: ValueKey('prompt-pay-${payment.kind.name}-${payment.id}'),
          onTap: onPay,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: payment.urgent
                    ? const [Color(0xFFFF6B82), Color(0xFFE0457B)]
                    : const [AppColors.blue, AppColors.violet],
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        copy.button,
                        style: AppTextStyles.button(Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.title,
          key: ValueKey('prompt-title-${payment.kind.name}-${payment.id}'),
          style: AppTextStyles.cardHeading(p.primaryText)
              .copyWith(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(copy.message, style: AppTextStyles.support(p.secondaryText)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: tint.withValues(alpha: 0.6)),
        color: Color.alphaBlend(
          tint.withValues(alpha: p.isDark ? 0.12 : 0.08),
          p.surface,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxWidth >= 560;
          final lead = Icon(icon, size: 28, color: tint);
          if (roomy) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                lead,
                const SizedBox(width: 14),
                Expanded(child: text),
                const SizedBox(width: 16),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  lead,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                ],
              ),
              const SizedBox(height: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}
