import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../auth/application/auth_providers.dart';
import '../../my_membership/application/membership_detail_providers.dart';
import '../../my_membership/domain/membership_detail.dart'
    show clock12, fmtDate;
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/presentation/widgets/player_header.dart';
import '../../venues/domain/venue.dart' show rupees;
import '../data/receipt_pdf.dart';
import '../domain/payment_receipt.dart';

/// "Payment Successful": opens by itself when a payment is received. Shows what was paid for (the membership, coaching programme or
/// booking) in detail, how it was paid, the venue, and lets the player download the PDF receipt.
class PaymentSuccessPage extends ConsumerStatefulWidget {
  const PaymentSuccessPage({
    super.key,
    required this.receipt,
    required this.onNavigate,
  });

  final PaymentReceipt receipt;

  /// Opens a route in the app (after this page and the payment page behind it are closed).
  final void Function(String route) onNavigate;

  @override
  ConsumerState<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends ConsumerState<PaymentSuccessPage> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Home, the membership page and the like must show the new state, not what they loaded before paying
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(playerHomeProvider.notifier).refresh();
      ref.invalidate(myMembershipDetailsProvider);
    });
  }

  Future<void> _download() async {
    setState(() => _saving = true);
    try {
      final r = widget.receipt;
      final player = ref.read(currentPlayerProvider);
      final logo = await ref.read(receiptLogoProvider)();
      final bytes = await buildReceiptPdf(
        r,
        playerName: player?.fullName,
        playerPhone: player?.phone,
        logoPng: logo,
      );
      await ref.read(receiptSaverProvider)(bytes, receiptFileName(r));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your receipt is ready.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("We couldn't create the receipt. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _go(String route) {
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    widget.onNavigate(route);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.receipt;
    final (headline, sub) = switch (r.kind) {
      PaymentKind.membership =>
        r.autopay && r.paidInr == 0
            ? (
                'AutoPay set up',
                'Your membership is active. Your first payment will be taken as scheduled.',
              )
            : ('Payment Successful', 'Your membership is now active.'),
      PaymentKind.coaching =>
        r.autopay && r.paidInr == 0
            ? (
                'AutoPay set up',
                "You're enrolled. Your first payment will be taken as scheduled.",
              )
            : ('Payment Successful', "You're enrolled in the programme."),
      PaymentKind.booking =>
        (r.totalInr > 0 && r.paidInr >= r.totalInr && r.amountInr < r.totalInr)
            ? ('Balance Paid', 'Your booking is now paid in full.')
            : ('Payment Successful', 'Your court booking is confirmed.'),
    };
    final paidOn = r.paidAt == null
        ? null
        : '${fmtDate(r.paidAt!)}, ${clock12('${r.paidAt!.hour}:${r.paidAt!.minute}')}';
    final detailRows = receiptDetailRows(r);

    Widget card(String title, IconData icon, List<Widget> rows, {Key? key}) =>
        Container(
          key: key,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: p.isDark ? const Color(0xFF2E3B63) : p.border,
            ),
            color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: p.isDark
                        ? const Color(0xFFB9A4FF)
                        : AppColors.violet,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.cardHeading(p.primaryText)
                          .copyWith(fontSize: 17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        );
    // label on the left, value on the right, one line under the other with a hairline between
    Widget row(String label, String value, {Key? key, bool bold = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.border.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // not a Flexible: Flexible and Expanded split the free space equally, which left the value stranded mid-row
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  label,
                  style: AppTextStyles.body(p.secondaryText)
                      .copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  key: key,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.body(p.primaryText).copyWith(
                    fontSize: 14.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    final viewsMembership = r.kind == PaymentKind.membership;
    return Scaffold(
      key: const ValueKey('pay-success'),
      backgroundColor: p.background,
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 940),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: GameAllLogo(height: 30)),
                    const SizedBox(height: 22),
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.4, end: 1),
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.elasticOut,
                        builder: (context, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Container(
                          key: const ValueKey('pay-check'),
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success.withValues(alpha: 0.16),
                            border: Border.all(
                              color: AppColors.success,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 30,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 56,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      headline,
                      key: const ValueKey('pay-success-title'),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.desktopHeroHeading(p.primaryText)
                          .copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sub,
                      key: const ValueKey('pay-success-text'),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(p.secondaryText),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        rupees(r.amountInr),
                        key: const ValueKey('pay-amount'),
                        style: AppTextStyles.desktopHeroHeading(
                          AppColors.success,
                        ).copyWith(fontSize: 38),
                      ),
                    ),
                    Center(
                      child: Text(
                        'paid to ${r.venueName}',
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Wide screens: the payment and the thing paid for sit side by side, the venue under them; narrow ones stack them.
                    LayoutBuilder(
                      builder: (context, c) {
                        final payment = card(
                          'Payment details',
                          Icons.receipt_long_outlined,
                          [
                            row(
                              'Receipt number',
                              r.receiptNo,
                              key: const ValueKey('pay-receipt-no'),
                              bold: true,
                            ),
                            if (paidOn != null)
                              row(
                                'Paid on',
                                paidOn,
                                key: const ValueKey('pay-paid-on'),
                              ),
                            if (r.methodLabel != null)
                              row(
                                'Payment method',
                                r.methodLabel!,
                                key: const ValueKey('pay-method'),
                              ),
                            if (r.reference != null)
                              row(
                                'Reference',
                                r.reference!,
                                key: const ValueKey('pay-reference'),
                              ),
                            if (r.totalInr > r.paidInr &&
                                r.paidInr > 0 &&
                                !r.autopay)
                              row(
                                'Balance to pay',
                                rupees(r.totalInr - r.paidInr),
                                key: const ValueKey('pay-balance'),
                              ),
                          ],
                          key: const ValueKey('pay-payment-card'),
                        );
                        final item = detailRows.isEmpty
                            ? null
                            : card(
                                '${r.kindLabel} details',
                                switch (r.kind) {
                                  PaymentKind.membership =>
                                    Icons.workspace_premium_outlined,
                                  PaymentKind.coaching => Icons.school_outlined,
                                  PaymentKind.booking =>
                                    Icons.event_available_outlined,
                                },
                                [
                                  for (final (k, v) in detailRows)
                                    row(k, v, key: ValueKey('pay-row-$k')),
                                ],
                                key: const ValueKey('pay-item-card'),
                              );
                        final venue = card(
                          'Venue',
                          Icons.location_on_outlined,
                          [
                            row(
                              'Venue',
                              r.venueName,
                              key: const ValueKey('pay-venue'),
                            ),
                            if (r.venuePlace != null &&
                                r.venuePlace!.isNotEmpty)
                              row('Location', r.venuePlace!),
                            if (r.venuePhone != null)
                              row('Contact', r.venuePhone!),
                          ],
                          key: const ValueKey('pay-venue-card'),
                        );
                        if (c.maxWidth >= 760) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: payment),
                                    if (item != null) ...[
                                      const SizedBox(width: 16),
                                      Expanded(child: item),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              venue,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            payment,
                            if (item != null) ...[
                              const SizedBox(height: 16),
                              item,
                            ],
                            const SizedBox(height: 16),
                            venue,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GameAllButton.gradient(
                              key: const ValueKey('pay-download'),
                              label: _saving
                                  ? 'Preparing receipt…'
                                  : 'Download receipt',
                              icon: Icons.download_rounded,
                              expand: true,
                              onPressed: _saving ? null : _download,
                            ),
                            const SizedBox(height: 10),
                            if (viewsMembership)
                              GameAllButton.secondary(
                                key: const ValueKey('pay-view'),
                                label: 'View membership',
                                icon: Icons.workspace_premium_outlined,
                                expand: true,
                                onPressed: () => _go(AppRoutes.myMembership),
                              ),
                            const SizedBox(height: 6),
                            TextButton(
                              key: const ValueKey('pay-done'),
                              onPressed: () => _go(AppRoutes.home),
                              child: Text(
                                'Back to Home',
                                style: AppTextStyles.body(p.secondaryText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
