import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/payment.dart';
import 'package:gameall_club_mobile/features/payments/payment_link_share.dart';

void main() {
  group('whatsappNumber', () {
    test('adds 91 to a bare mobile and strips punctuation', () {
      expect(whatsappNumber('98765 43210'), '919876543210');
      expect(whatsappNumber('+91 98765-43210'), '919876543210');
      expect(whatsappNumber('919876543210'), '919876543210');
    });
    test('is null for something that is not a number', () {
      expect(whatsappNumber('12345'), isNull);
      expect(whatsappNumber(null), isNull);
    });
  });

  group('message and share link', () {
    final message = paymentLinkMessage(guestName: 'Arun', description: 'Court 1 · 20 Oct, 6:00 PM', amountLabel: '₹800', url: 'https://rzp.io/i/abc');
    test('greets, states the amount and carries the link', () {
      expect(message, 'Hi Arun, please pay ₹800 to confirm your booking (Court 1 · 20 Oct, 6:00 PM): https://rzp.io/i/abc');
    });
    test('opens WhatsApp on the guest number, or the contact picker without one', () {
      expect(whatsappShareUri('9876543210', message).toString(), startsWith('https://wa.me/919876543210?text='));
      expect(whatsappShareUri('', message).toString(), startsWith('https://wa.me/?text='));
    });
  });

  group('BookingPaymentLink.fromJson', () {
    test('an open link', () {
      final l = BookingPaymentLink.fromJson({
        'paymentOrderId': 'po1',
        'bookingId': 'b1',
        'shortUrl': 'https://rzp.io/i/x',
        'amountMinor': 80000,
        'currency': 'INR',
        'status': 'CREATED',
        'paid': false,
        'expiresAt': '2026-10-16T10:00:00.000Z',
      }, fallbackBookingId: 'b1');
      expect(l.isOpen, true);
      expect(l.shortUrl, 'https://rzp.io/i/x');
      expect(l.amountMinor, 80000);
    });
    test('paid wins over a stale status, and a closed link is not open', () {
      expect(BookingPaymentLink.fromJson({'paid': true, 'status': 'CREATED'}, fallbackBookingId: 'b1').paid, true);
      expect(BookingPaymentLink.fromJson({'status': 'PAID'}, fallbackBookingId: 'b1').status, 'PAID');
      final closed = BookingPaymentLink.fromJson({'status': 'EXPIRED'}, fallbackBookingId: 'b1');
      expect(closed.isClosed, true);
      expect(closed.isOpen, false);
      expect(closed.bookingId, 'b1');
    });
  });
}
