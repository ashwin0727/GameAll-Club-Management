import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/payment_receipt_repository.dart';
import '../data/player_booking_repository.dart';
import '../domain/payment_receipt.dart';
import '../presentation/payment_progress_page.dart';

/// The data source. Tests override this with a fake.
final paymentReceiptRepositoryProvider = Provider<PaymentReceiptRepository>(
  (ref) => SupabasePaymentReceiptRepository(),
);

/// What the payment progress page is told to pay: the item's id and the page to pay on (null: it turned out to be paid already).
class PaymentTarget {
  const PaymentTarget({required this.id, required this.link});

  final String id;
  final Uri? link;
}

/// One payment the player has just asked to make (Pay & Enroll, Complete payment, Retry payment…).
class PaymentJob {
  const PaymentJob({
    required this.kind,
    required this.title,
    required this.prepare,
    this.venueName,
    this.balance = false,
  });

  final PaymentKind kind;

  /// "Court Time Membership": shown on the progress page while the payment is prepared.
  final String title;
  final String? venueName;

  /// Paying what is left of a booking whose advance is already paid: it only counts as paid once the whole amount is.
  final bool balance;

  /// Creates what has to exist (a pending membership or enrolment, a payment link) and returns it. May throw an exception that has a
  /// `message` the player can read.
  final Future<PaymentTarget> Function() prepare;
}

/// Opens the full-screen payment progress page for [job]: it prepares the payment, opens the payment page, waits for the payment to be
/// confirmed and then shows the "Payment Successful" page. [onNavigate] opens a route in the app (the success page's "View …" button).
Future<void> openPaymentFlow(
  BuildContext context, {
  required PaymentJob job,
  required void Function(String route) onNavigate,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => PaymentProgressPage(job: job, onNavigate: onNavigate),
  ),
);

/// The words of an exception the app threw for the player, or [fallback].
String paymentErrorText(Object error, {String fallback = "We couldn't start your payment. Please try again."}) {
  try {
    final m = (error as dynamic).message;
    if (m is String && m.trim().isNotEmpty) return m;
  } catch (_) {}
  return fallback;
}

/// Makes the booking behind Guest Booking's "Book Now". Tests override this with a fake.
final playerBookingRepositoryProvider = Provider<PlayerBookingRepository>(
  (ref) => SupabasePlayerBookingRepository(),
);
