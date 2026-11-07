import 'package:gameall_player/features/payments/data/payment_receipt_repository.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';

/// A stand-in for the receipt service: [receipt] says "pending" until [paidAfterSyncs] syncs have happened, then "paid".
class FakePaymentReceipts implements PaymentReceiptRepository {
  FakePaymentReceipts({
    this.paidAfterSyncs = 2,
    this.kindOverride,
    this.failReceipt = false,
  });

  /// How many `sync` calls it takes before the payment shows as received (a very large number: never).
  int paidAfterSyncs; // 2: a page that checks by itself on load uses the first
  final PaymentKind? kindOverride;
  final bool failReceipt;
  int syncs = 0;
  final calls = <String>[];

  PaymentReceipt _make(PaymentKind kind, String id, PaymentState state) =>
      PaymentReceipt(
        kind: kindOverride ?? kind,
        id: id,
        state: state,
        title: 'Court Time Membership',
        venueName: 'Ace Arena',
        venuePlace: 'Anna Nagar, Chennai',
        venuePhone: '9000000009',
        totalInr: 1400,
        paidInr: state == PaymentState.paid ? 1400 : 0,
        amountInr: 1400,
        receiptNo: 'RCP-1A2B3C4D',
        method: 'upi',
        reference: 'pay_TEST123',
        paidAt: DateTime(2026, 11, 7, 18, 30),
        details: const {
          'membershipRef': 'MBR-ACE-000012',
          'planName': 'Court Time Membership',
          'durationDays': 30,
          'startDate': '2026-11-07',
          'endDate': '2026-12-07',
          'slot': {
            'sport': 'Badminton',
            'court': 'Court 1',
            'daysOfWeek': [1, 3, 5],
            'startTime': '18:00',
            'endTime': '19:00',
          },
          'programName': 'Beginner Program',
          'sport': 'Badminton',
          'coach': 'Coach Arjun',
        },
      );

  @override
  Future<PaymentReceipt?> receipt(PaymentKind kind, String id) async {
    calls.add('receipt $id');
    if (failReceipt) throw Exception('offline');
    return _make(
      kind,
      id,
      syncs >= paidAfterSyncs ? PaymentState.paid : PaymentState.pending,
    );
  }

  @override
  Future<PaymentReceipt?> sync(PaymentKind kind, String id) async {
    calls.add('sync $id');
    syncs++;
    return receipt(kind, id);
  }
}
