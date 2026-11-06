import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/external_links.dart';
import '../../../../core/widgets/pressable.dart';
import '../../application/player_home_controller.dart';
import '../../data/pending_payment_repository.dart';
import '../../domain/player_dashboard_models.dart';

/// "Complete your payment" prompts at the top of Home: one per membership, coaching enrolment or booking that is not fully paid.
/// A failed or late payment is shown in red and spoken about more firmly; each has a button that opens the Razorpay page right here.
/// Coming back from that page reloads Home, so a prompt disappears by itself once the payment has gone through.
class PaymentPrompts extends ConsumerStatefulWidget {
  const PaymentPrompts({super.key, required this.payments});

  final List<PendingPayment> payments;

  @override
  ConsumerState<PaymentPrompts> createState() => _PaymentPromptsState();
}

class _PaymentPromptsState extends ConsumerState<PaymentPrompts>
    with WidgetsBindingObserver {
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the payment page (or the browser tab): look again at what is paid.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playerHomeProvider.notifier).refresh();
    }
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pay(PendingPayment p) async {
    final key = '${p.kind.name}-${p.id}';
    setState(() => _busy = key);
    try {
      final link = await ref
          .read(pendingPaymentRepositoryProvider)
          .paymentLink(p);
      if (link == null) {
        _toast('That payment is already done. Refreshing…');
        await ref.read(playerHomeProvider.notifier).refresh();
        return;
      }
      final opened = await ref.read(linkOpenerProvider)(link);
      if (!opened) {
        throw const PaymentLinkException(
          "We couldn't open the payment page. Please try again.",
        );
      }
      _toast(
        'Finish the payment on the page that opened. This will update here once it is done.',
      );
    } on PaymentLinkException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("We couldn't open the payment page. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.payments.isEmpty) return const SizedBox.shrink();
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
