import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/repository_providers.dart';
import 'payment_link_share.dart';

/// "Pay Online" for a guest booking. The player is not at the counter, so no checkout opens on this phone;
/// instead a one-time payment link is made for the booking and shown here to copy / share (WhatsApp, any app),
/// and the sheet watches for the payment. The booking only turns Paid when Razorpay confirms the money — the
/// webhook, or this sheet's own status check. Resolves true once the payment is confirmed.
Future<bool> showBookingPaymentLinkSheet(
  BuildContext context, {
  required String facilityId,
  required String bookingId,
  required String guestName,
  required String? guestPhone,
  required String description,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.tokens.surface0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _LinkSheet(
      facilityId: facilityId,
      bookingId: bookingId,
      guestName: guestName,
      guestPhone: guestPhone,
      description: description,
    ),
  );
  return paid ?? false;
}

class _LinkSheet extends ConsumerStatefulWidget {
  const _LinkSheet({
    required this.facilityId,
    required this.bookingId,
    required this.guestName,
    required this.guestPhone,
    required this.description,
  });

  final String facilityId;
  final String bookingId;
  final String guestName;
  final String? guestPhone;
  final String description;

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 10);

  BookingPaymentLink? _link;
  String? _error;
  bool _busy = true;
  bool _checking = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // The player usually pays in another app, so check the moment staff come back to this one.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_link?.isOpen ?? false)) _check(manual: false);
  }

  void _apply(BookingPaymentLink next) {
    if (!mounted) return;
    setState(() => _link = next);
    _timer?.cancel();
    if (next.isOpen) {
      _timer = Timer.periodic(_pollEvery, (_) => _check(manual: false));
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _apply(await ref.read(paymentRepositoryProvider).createBookingPaymentLink(facilityId: widget.facilityId, bookingId: widget.bookingId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check({required bool manual}) async {
    if (_checking) return;
    if (manual) setState(() => _checking = true);
    try {
      _apply(await ref.read(paymentRepositoryProvider).checkBookingPaymentLink(facilityId: widget.facilityId, bookingId: widget.bookingId));
    } on AppException catch (e) {
      if (manual && mounted) setState(() => _error = e.message);
    } finally {
      if (manual && mounted) setState(() => _checking = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _apply(await ref.read(paymentRepositoryProvider).cancelBookingPaymentLink(facilityId: widget.facilityId, bookingId: widget.bookingId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _amountLabel {
    final minor = _link?.amountMinor;
    return minor == null ? 'the amount' : Formatters.currencyInr(minor / 100);
  }

  String get _message => paymentLinkMessage(
        guestName: widget.guestName,
        description: widget.description,
        amountLabel: _amountLabel,
        url: _link?.shortUrl ?? '',
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final link = _link;

    Widget body;
    if (link == null && _busy) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (link == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error ?? 'Could not create the payment link.', style: TextStyle(color: tokens.destructive, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text('The booking is saved. You can try again, or collect payment at the venue.', style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: _create, child: const Text('Try Again')),
        ],
      );
    } else if (link.paid) {
      body = Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 44, color: tokens.success),
          const SizedBox(height: AppSpacing.sm),
          const Text('Payment Received', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text('The booking is confirmed and marked Paid. Nothing to collect at the venue.',
              textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
        ],
      );
    } else if (link.isClosed) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.status == 'EXPIRED' ? 'This link has expired' : 'This link was cancelled', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text('It can no longer be paid. Generate a new one to collect $_amountLabel.', style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: _busy ? null : _create, child: const Text('Generate a New Link')),
        ],
      );
    } else {
      final url = link.shortUrl ?? '';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this link with ${widget.guestName.trim().isEmpty ? 'the player' : widget.guestName.trim()}. They pay $_amountLabel on their own '
            'phone — the booking is confirmed automatically once the payment goes through.',
            style: TextStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tokens.borderColor),
            ),
            child: SelectableText(url, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: url.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link Copied')));
                          }
                        },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: url.isEmpty ? null : () => SharePlus.instance.share(ShareParams(text: _message)),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: url.isEmpty ? null : () => launchUrl(whatsappShareUri(widget.guestPhone, _message), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Send on WhatsApp'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _checking ? null : () => _check(manual: true),
                  child: Text(_checking ? 'Checking…' : 'Check payment status'),
                ),
              ),
              TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel Link')),
            ],
          ),
          if (link.expiresAt != null)
            Text('Valid until ${Formatters.dateTimeShort(link.expiresAt!.toLocal())}.',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
        ],
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link_rounded, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('Payment Link', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  if (link != null && link.isOpen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: tokens.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text('Waiting for Payment', style: TextStyle(color: tokens.warning, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              body,
              if (_error != null && link != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 12)),
              ],
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context, link?.paid ?? false), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
