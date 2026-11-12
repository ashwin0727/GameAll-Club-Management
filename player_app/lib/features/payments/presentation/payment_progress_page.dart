import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../player_home/presentation/widgets/player_header.dart';
import '../../venues/domain/venue.dart' show rupees;
import '../application/payment_flow.dart';
import '../domain/payment_receipt.dart';
import 'payment_success_page.dart';

enum _Stage { preparing, opening, waiting, failed, timedOut, error }

/// The full-screen "Processing your payment" page every pay button opens.
///
///  1 · prepares the payment (creates the pending membership / enrolment and the payment link),
///  2 · opens the secure payment page (a new tab on the web, the browser or UPI app on Android),
///  3 · keeps asking, every few seconds and the moment the player comes back, whether the payment has been received,
///  4 · and, once it has, replaces itself with the "Payment Successful" page.
/// The player can open the payment page again, check at once, or cancel at any time.
class PaymentProgressPage extends ConsumerStatefulWidget {
  const PaymentProgressPage({
    super.key,
    required this.job,
    required this.onNavigate,
    this.pollEvery = const Duration(seconds: 3),
    this.giveUpAfter = const Duration(minutes: 10),
  });

  final PaymentJob job;
  final void Function(String route) onNavigate;

  /// How often the payment is checked while waiting.
  final Duration pollEvery;

  /// After this long without a payment the page stops checking by itself and says so.
  final Duration giveUpAfter;

  @override
  ConsumerState<PaymentProgressPage> createState() =>
      _PaymentProgressPageState();
}

class _PaymentProgressPageState extends ConsumerState<PaymentProgressPage>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.preparing;
  PaymentTarget? _target;
  PaymentReceipt? _receipt;
  String? _message;
  bool _checking = false;
  bool _done = false;
  DateTime? _waitingSince;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the payment page (or the browser tab): look at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.waiting) {
      _check();
    }
  }

  /// Whether the payment this page waits for is in: the whole amount for a balance payment, otherwise what the receipt says.
  bool _paidNow(PaymentReceipt? r) {
    if (r == null) return false;
    return widget.job.balance
        ? (r.totalInr > 0 && r.paidInr >= r.totalInr)
        : r.isPaid;
  }

  Future<void> _run() async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _stage = _Stage.preparing;
        _message = null;
      });
    }
    try {
      final target = await widget.job.prepare();
      if (!mounted) return;
      _target = target;
      // what is being paid, for the page (amount, name): best effort
      try {
        _receipt = await ref
            .read(paymentReceiptRepositoryProvider)
            .receipt(widget.job.kind, target.id);
      } catch (_) {}
      if (!mounted) return;
      if (target.link == null || _paidNow(_receipt)) {
        return _succeed();
      }
      await _open();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _message = paymentErrorText(e);
      });
    }
  }

  Future<void> _open() async {
    final link = _target?.link;
    if (link == null) return;
    setState(() => _stage = _Stage.opening);
    final opened = await ref.read(linkOpenerProvider)(link);
    if (!mounted) return;
    if (!opened) {
      setState(() {
        _stage = _Stage.error;
        _message = "We couldn't open the payment page. Please try again.";
      });
      return;
    }
    setState(() {
      _stage = _Stage.waiting;
      _waitingSince = DateTime.now();
      _message = null;
    });
    _scheduleNext();
  }

  /// How long to wait before the next check. The first two minutes use [PaymentProgressPage.pollEvery]; after that the player has
  /// plainly stepped away, so the checks thin out (3x, then 6x as slow) instead of asking the server every few seconds for ten minutes.
  /// "I've paid — check now" and coming back to the app still check at once.
  Duration _nextDelay() {
    final since = _waitingSince;
    final waited = since == null
        ? Duration.zero
        : DateTime.now().difference(since);
    if (waited < const Duration(minutes: 2)) return widget.pollEvery;
    if (waited < const Duration(minutes: 5)) return widget.pollEvery * 3;
    return widget.pollEvery * 6;
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_nextDelay(), () async {
      await _check();
      if (mounted && !_done && _stage == _Stage.waiting) _scheduleNext();
    });
  }

  Future<void> _check({bool manual = false}) async {
    final target = _target;
    if (target == null || _checking || _done) return;
    _checking = true;
    try {
      final r = await ref
          .read(paymentReceiptRepositoryProvider)
          .sync(widget.job.kind, target.id);
      if (!mounted || _done) return;
      if (r != null) _receipt = r;
      if (_paidNow(r)) return _succeed();
      final since = _waitingSince;
      if (since != null &&
          DateTime.now().difference(since) >= widget.giveUpAfter) {
        _timer?.cancel();
        setState(() => _stage = _Stage.timedOut);
      } else if (manual) {
        setState(
          () => _message = (r?.state == PaymentState.failed)
              ? "That payment didn't go through. You can try again."
              : "We haven't received your payment yet. If you've just paid, give it a few seconds.",
        );
      } else if (r?.state == PaymentState.failed && _message == null) {
        setState(
          () => _message = "An earlier attempt didn't go through. Finish the payment on the page that opened, or try again.",
        );
      } else {
        setState(() {});
      }
    } catch (_) {
      // a hiccup: the next check tries again
    } finally {
      _checking = false;
    }
  }

  void _succeed() {
    if (_done || !mounted) return;
    _done = true;
    _timer?.cancel();
    final r = _receipt;
    if (r == null) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            PaymentSuccessPage(receipt: r, onNavigate: widget.onNavigate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final failed = _stage == _Stage.error || _stage == _Stage.timedOut;
    final r = _receipt;
    final amount = (r != null && r.totalInr > 0)
        ? (widget.job.balance
              ? (r.totalInr - r.paidInr).clamp(0, r.totalInr)
              : r.totalInr)
        : null;

    Widget step(String label, _StepState s, {Key? key}) {
      final color = switch (s) {
        _StepState.done => AppColors.success,
        _StepState.active => p.highlight,
        _StepState.todo => p.mutedText,
      };
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: switch (s) {
                _StepState.done => const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 24,
                ),
                _StepState.active => Padding(
                  padding: const EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: p.highlight,
                  ),
                ),
                _StepState.todo => Icon(
                  Icons.radio_button_unchecked_rounded,
                  color: p.mutedText,
                  size: 22,
                ),
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style:
                    AppTextStyles.body(
                      s == _StepState.todo ? p.mutedText : p.primaryText,
                    ).copyWith(
                      fontWeight: s == _StepState.active
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: s == _StepState.done ? color : null,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final prepared = _stage != _Stage.preparing && !(failed && _target == null);
    final opened =
        _stage == _Stage.waiting ||
        _stage == _Stage.timedOut ||
        (_stage == _Stage.error && _target != null && _waitingSince != null);
    final steps = [
      step(
        'Creating your payment',
        prepared || _target != null
            ? _StepState.done
            : (failed ? _StepState.todo : _StepState.active),
        key: const ValueKey('pay-step-prepare'),
      ),
      step(
        'Opening the secure payment page',
        opened
            ? _StepState.done
            : (_stage == _Stage.opening ? _StepState.active : _StepState.todo),
        key: const ValueKey('pay-step-open'),
      ),
      step(
        'Confirming your payment',
        _stage == _Stage.waiting ? _StepState.active : _StepState.todo,
        key: const ValueKey('pay-step-confirm'),
      ),
    ];

    final (title, subtitle) = switch (_stage) {
      _Stage.preparing => (
        'Preparing your payment…',
        'Please wait a moment. Please do not close or go back.',
      ),
      _Stage.opening => (
        'Opening the payment page…',
        'A secure Razorpay page is opening. If it is blocked, tap "Open payment page".',
      ),
      _Stage.waiting => (
        'Waiting for your payment…',
        'Finish the payment on the page that opened. This screen updates by itself the moment it is received. Please do not close it.',
      ),
      _Stage.timedOut => (
        'Still waiting for your payment',
        "We haven't received it yet. If you have paid, it can take a minute or two to show up. You can check again.",
      ),
      _Stage.failed => (
        "Your payment didn't go through",
        'Nothing has been charged. You can try again.',
      ),
      _Stage.error => (
        "We couldn't start your payment",
        _message ?? 'Please try again.',
      ),
    };

    return PopScope(
      child: Scaffold(
        key: const ValueKey('pay-progress'),
        backgroundColor: p.background,
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: GameAllLogo(height: 30)),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: p.isDark
                                ? const Color(0xFF2E3B63)
                                : p.border,
                          ),
                          color: p.surface.withValues(
                            alpha: p.isDark ? 0.7 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C5CFF)
                                  .withValues(alpha: p.isDark ? 0.2 : 0.08),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 72,
                              height: 72,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (failed)
                                    const SizedBox.shrink()
                                  else
                                    SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: CircularProgressIndicator(
                                        key: const ValueKey('pay-spinner'),
                                        strokeWidth: 5,
                                        color: p.highlight,
                                      ),
                                    ),
                                  Icon(
                                    failed
                                        ? Icons.error_outline_rounded
                                        : Icons.lock_outline_rounded,
                                    size: failed ? 52 : 28,
                                    color: failed
                                        ? AppColors.danger
                                        : p.primaryText,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              title,
                              key: const ValueKey('pay-stage-title'),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.sectionHeading(p.primaryText)
                                  .copyWith(fontSize: 21),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              key: const ValueKey('pay-stage-text'),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body(p.secondaryText),
                            ),
                            const SizedBox(height: 14),
                            // what is being paid
                            Container(
                              key: const ValueKey('pay-summary'),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: p.isDark
                                    ? const Color(0xFF111A35)
                                    : p.elevated,
                                border: Border.all(
                                  color: p.isDark
                                      ? const Color(0xFF2E3B63)
                                      : p.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.job.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.cardHeading(
                                            p.primaryText,
                                          ).copyWith(fontSize: 15.5),
                                        ),
                                        if ((widget.job.venueName ??
                                                r?.venueName ??
                                                '')
                                            .isNotEmpty)
                                          Text(
                                            widget.job.venueName ??
                                                r!.venueName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.support(
                                              p.secondaryText,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (amount != null)
                                    Text(
                                      rupees(amount),
                                      key: const ValueKey('pay-summary-amount'),
                                      style:
                                          AppTextStyles.cardHeading(
                                            p.primaryText,
                                          ).copyWith(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...steps,
                            if (_message != null &&
                                _stage == _Stage.waiting) ...[
                              const SizedBox(height: 10),
                              Container(
                                key: const ValueKey('pay-note'),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.warning.withValues(
                                    alpha: 0.12,
                                  ),
                                  border: Border.all(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _message!,
                                  style: AppTextStyles.support(p.primaryText),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            if (_stage == _Stage.waiting ||
                                _stage == _Stage.timedOut) ...[
                              GameAllButton.gradient(
                                key: const ValueKey('pay-check-now'),
                                label: "I've paid — check now",
                                expand: true,
                                onPressed: () => _check(manual: true),
                              ),
                              const SizedBox(height: 10),
                              GameAllButton.secondary(
                                key: const ValueKey('pay-reopen'),
                                label: 'Open payment page again',
                                expand: true,
                                onPressed: _open,
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (_stage == _Stage.opening)
                              GameAllButton.secondary(
                                key: const ValueKey('pay-reopen'),
                                label: 'Open payment page',
                                expand: true,
                                onPressed: _open,
                              ),
                            if (_stage == _Stage.error ||
                                _stage == _Stage.failed) ...[
                              GameAllButton.gradient(
                                key: const ValueKey('pay-retry'),
                                label: 'Try again',
                                expand: true,
                                onPressed: _run,
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (_stage != _Stage.preparing)
                              TextButton(
                                key: const ValueKey('pay-cancel'),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: Text(
                                  _stage == _Stage.waiting
                                      ? 'Cancel and go back'
                                      : 'Close',
                                  style: AppTextStyles.body(p.secondaryText),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: p.mutedText,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Payments are processed securely by Razorpay.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.support(p.mutedText),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StepState { done, active, todo }
