import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/booking_cancellation_quote.dart';
import '../../data/repositories/repository_providers.dart';

/// What the club decided in the cancel dialog: follow the schedule ([overridePercent] null) or refund its own % with a [reason].
class CancelDecision {
  const CancelDecision({this.overridePercent, this.overrideReason, this.reason});

  final int? overridePercent;
  final String? overrideReason;

  /// Why the booking is being cancelled (optional).
  final String? reason;
}

/// "Cancel Booking": says, before anything happens, how many hours are left, the % deducted, what is refunded and how (online
/// through Razorpay, cash handed back at the club). A booking that is only part-paid (the 50% advance) gets no refund by default;
/// the club can change the refund % for this one cancellation, with a reason. Returns null when the club keeps the booking.
Future<CancelDecision?> showCancelQuoteDialog(
  BuildContext context, {
  required String bookingId,
  String? subtitle,
}) {
  return showDialog<CancelDecision>(
    context: context,
    builder: (_) => _CancelQuoteDialog(bookingId: bookingId, subtitle: subtitle),
  );
}

/// The sentence shown after a cancellation that moved money.
String cancelledNote(Map<String, dynamic>? c) {
  if (c == null) return 'Booking cancelled.';
  final paid = (c['paid_minor'] as num?)?.toInt() ?? 0;
  final refund = (c['refund_minor'] as num?)?.toInt() ?? 0;
  final online = (c['online_refund_minor'] as num?)?.toInt() ?? 0;
  final offline = (c['offline_refund_due_minor'] as num?)?.toInt() ?? 0;
  if (paid <= 0) return 'Booking cancelled.';
  if (refund <= 0) return 'Booking cancelled. No refund applies.';
  final parts = <String>['Booking cancelled.'];
  if (online > 0) {
    parts.add('${Formatters.currencyInr((online / 100).round())} is being refunded through Razorpay (5–7 working days).');
  }
  if (offline > 0) {
    parts.add('${Formatters.currencyInr((offline / 100).round())} was paid in cash: please hand it back at the club.');
  }
  return parts.join(' ');
}

class _CancelQuoteDialog extends ConsumerStatefulWidget {
  const _CancelQuoteDialog({required this.bookingId, this.subtitle});

  final String bookingId;
  final String? subtitle;

  @override
  ConsumerState<_CancelQuoteDialog> createState() => _CancelQuoteDialogState();
}

class _CancelQuoteDialogState extends ConsumerState<_CancelQuoteDialog> {
  BookingCancellationQuote? _quote;
  bool _failed = false;
  bool _override = false;
  final _percent = TextEditingController(text: '100');
  final _overrideReason = TextEditingController();
  final _reason = TextEditingController();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _percent.dispose();
    _overrideReason.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? get _overridePercent {
    if (!_override) return null;
    final n = int.tryParse(_percent.text.trim());
    return n != null && n >= 0 && n <= 100 ? n : null;
  }

  Future<void> _load() async {
    final gen = ++_generation;
    final q = await ref.read(refundRepositoryProvider).bookingCancellationQuote(
      widget.bookingId,
      overridePercent: _overridePercent,
    );
    if (!mounted || gen != _generation) return;
    setState(() {
      _quote = q;
      _failed = q == null;
    });
  }

  bool get _ready {
    if (_quote == null) return false;
    if (!_override) return true;
    return _overridePercent != null && _overrideReason.text.trim().length >= 3;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _quote;
    String money(int inr) => Formatters.currencyInr(inr);

    Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    );

    return AlertDialog(
      key: const ValueKey('cancel-quote-dialog'),
      title: const Text('Cancel Booking'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.subtitle != null) ...[
                Text(widget.subtitle!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
              ],
              if (_failed)
                Text(
                  "We couldn't work out the refund just now. Close this and try again.",
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (q == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Container(
                  key: const ValueKey('cancel-quote-message'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: (q.refundMinor > 0 || q.paidMinor == 0 ? theme.colorScheme.primary : theme.colorScheme.error).withValues(alpha: 0.10),
                  ),
                  child: Text(q.message),
                ),
                if (q.paidMinor > 0) ...[
                  const SizedBox(height: 10),
                  row('Amount paid', money(q.paidInr)),
                  row(
                    'Deduction (${q.deductionPercent}%)',
                    q.deductionMinor == 0 ? money(0) : '− ${money(q.deductionInr)}',
                    color: q.deductionMinor == 0 ? null : theme.colorScheme.error,
                  ),
                  const Divider(),
                  row('Refund to the customer', money(q.refundInr), bold: true),
                  if (q.onlineRefundMinor > 0)
                    row('  Refunded online through Razorpay', money(q.onlineRefundInr)),
                  if (q.offlineRefundDueMinor > 0)
                    row('  Cash to hand back at the club', money(q.offlineRefundDueInr), color: Colors.orange.shade700),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    key: const ValueKey('cancel-override'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _override,
                    onChanged: (v) {
                      setState(() => _override = v ?? false);
                      _load();
                    },
                    title: const Text('Change the refund for this cancellation (club decision)'),
                  ),
                  if (_override) ...[
                    TextField(
                      key: const ValueKey('cancel-override-percent'),
                      controller: _percent,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Refund (% of what was paid)'),
                      onChanged: (_) {
                        setState(() {});
                        _load();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('cancel-override-reason'),
                      controller: _overrideReason,
                      decoration: const InputDecoration(labelText: 'Reason (required)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('cancel-reason'),
                  controller: _reason,
                  decoration: const InputDecoration(labelText: 'Reason for cancelling (optional)'),
                ),
                ExpansionTile(
                  key: const ValueKey('cancel-rules'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('See the refund rules'),
                  children: [
                    for (final (label, pct) in bookingCancellationSchedule)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text('Cancelled with $label left', style: theme.textTheme.bodySmall)),
                            Text('$pct% deducted', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Applies when the booking is paid in full. If only the 50% advance is paid there is no refund, unless the club changes it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-quote-keep'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep Booking'),
        ),
        FilledButton(
          key: const ValueKey('cancel-quote-confirm'),
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          onPressed: _ready
              ? () => Navigator.of(context).pop(
                  CancelDecision(
                    overridePercent: _overridePercent,
                    overrideReason: _overridePercent != null ? _overrideReason.text.trim() : null,
                    reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
                  ),
                )
              : null,
          child: const Text('Cancel Booking'),
        ),
      ],
    );
  }
}
