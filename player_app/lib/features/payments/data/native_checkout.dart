import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/payment_receipt.dart';

/// Razorpay's own payment sheet inside the app (Android). It lists the UPI apps already on the phone (GPay, PhonePe, Paytm…) and also
/// cards, netbanking and wallets, so the player is never sent to a web page first. The web build cannot use it and keeps the hosted page.
bool get nativeCheckoutAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// What the sheet needs to open: a Razorpay ORDER (a booking) or a SUBSCRIPTION (an AutoPay mandate). The server makes both and sends
/// only the public key with them; the amount of an order is the server's, never the app's.
class CheckoutRequest {
  const CheckoutRequest({
    required this.kind,
    required this.itemId,
    required this.keyId,
    this.orderId,
    this.subscriptionId,
    this.paymentOrderId,
    this.amountMinor,
    this.description = 'GameAll',
    this.name,
    this.contact,
    this.email,
    this.timeoutSeconds = 600,
  });

  final PaymentKind kind;

  /// The booking, membership or coaching enrolment being paid.
  final String itemId;
  final String keyId;
  final String? orderId;
  final String? subscriptionId;

  /// The server's own record of the order (bookings), sent back when the result is verified.
  final String? paymentOrderId;
  final int? amountMinor;
  final String description;

  /// The payer, so the sheet goes straight to the payment options instead of asking for a mobile number and an email first.
  final String? name;
  final String? contact;
  final String? email;

  /// How long the sheet stays open before Razorpay closes it by itself. A held court gets the time it has left.
  final int timeoutSeconds;

  bool get isSubscription => subscriptionId != null;

  /// The same checkout for this payer.
  CheckoutRequest withPayer({String? name, String? contact, String? email}) =>
      CheckoutRequest(
        kind: kind,
        itemId: itemId,
        keyId: keyId,
        orderId: orderId,
        subscriptionId: subscriptionId,
        paymentOrderId: paymentOrderId,
        amountMinor: amountMinor,
        description: description,
        name: name,
        contact: contact,
        email: email,
        timeoutSeconds: timeoutSeconds,
      );

  /// The same checkout that closes itself after [seconds].
  CheckoutRequest withTimeout(int seconds) => CheckoutRequest(
        kind: kind,
        itemId: itemId,
        keyId: keyId,
        orderId: orderId,
        subscriptionId: subscriptionId,
        paymentOrderId: paymentOrderId,
        amountMinor: amountMinor,
        description: description,
        name: name,
        contact: contact,
        email: email,
        timeoutSeconds: seconds,
      );
}

sealed class CheckoutResult {
  const CheckoutResult();
}

/// The sheet says it was paid. This is a claim, not proof: the server checks it.
class CheckoutPaid extends CheckoutResult {
  const CheckoutPaid({
    required this.paymentId,
    required this.signature,
    this.orderId,
    this.subscriptionId,
  });
  final String paymentId;
  final String signature;
  final String? orderId;
  final String? subscriptionId;
}

/// The player closed the sheet.
class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);
  final String message;
}

/// Opens the sheet and answers when the player is done with it. Tests replace this with a fake.
typedef NativeCheckout = Future<CheckoutResult> Function(CheckoutRequest);

final nativeCheckoutProvider = Provider<NativeCheckout>(
  (ref) => _openRazorpaySheet,
);

/// Checks, on the server, what the sheet claimed: the signature, that the payment is for this item and that Razorpay really has it.
/// True only when the server says so. The razorpay-webhook records the payment whether or not this is ever called.
typedef CheckoutVerifier =
    Future<bool> Function(CheckoutRequest request, CheckoutPaid paid);

final checkoutVerifierProvider = Provider<CheckoutVerifier>(
  (ref) => _verifyOnServer,
);

/// The sheets the server asked for, found again by the page they belong to. The payment repositories keep the checkout they were given
/// here, under the address of the hosted page (the fallback), and the progress page picks it up when it is time to pay. A page that has
/// no entry here simply opens the hosted page as before.
class CheckoutStore {
  CheckoutStore._();
  static final CheckoutStore instance = CheckoutStore._();

  final Map<String, CheckoutRequest> _byLink = {};

  /// The address a checkout stands for: the hosted page when there is one, otherwise a made-up address that is never opened.
  Uri register(CheckoutRequest request, {Uri? hostedPage}) {
    final key =
        hostedPage ??
        Uri(
          scheme: 'gameall-checkout',
          host: request.kind.wire,
          path: '/${request.itemId}',
        );
    _byLink[key.toString()] = request;
    return key;
  }

  CheckoutRequest? forLink(Uri? link) =>
      link == null ? null : _byLink[link.toString()];

  /// Forget everything: for tests.
  @visibleForTesting
  void clear() => _byLink.clear();
}

/// Reads what a payment function sent back and, when it holds what the in-app sheet needs, remembers it. Returns the address the
/// progress page opens: the hosted page when the server sent one, otherwise a made-up one for the sheet. Null when the server sent
/// neither a page nor a checkout.
///   * a booking: `{ checkout: { keyId, orderId, amountMinor }, paymentOrderId }`
///   * AutoPay (membership, coaching): `{ keyId, subscriptionId, shortUrl }`
Uri? checkoutLinkFrom(
  Map<dynamic, dynamic> data, {
  required PaymentKind kind,
  required String itemId,
  required String description,
}) {
  final hosted = switch (data['shortUrl']) {
    final String s when s.isNotEmpty => Uri.tryParse(s),
    _ => null,
  };
  if (!nativeCheckoutAvailable) return hosted;

  CheckoutRequest? request;
  final c = data['checkout'];
  if (c is Map && c['keyId'] is String && c['orderId'] is String) {
    request = CheckoutRequest(
      kind: kind,
      itemId: itemId,
      keyId: c['keyId'] as String,
      orderId: c['orderId'] as String,
      paymentOrderId: data['paymentOrderId'] as String?,
      amountMinor: (c['amountMinor'] as num?)?.toInt(),
      description: description,
    );
  } else if (data['keyId'] is String && data['subscriptionId'] is String) {
    request = CheckoutRequest(
      kind: kind,
      itemId: itemId,
      keyId: data['keyId'] as String,
      subscriptionId: data['subscriptionId'] as String,
      description: description,
    );
  }
  if (request == null) return hosted;
  return CheckoutStore.instance.register(request, hostedPage: hosted);
}

Future<CheckoutResult> _openRazorpaySheet(CheckoutRequest r) {
  final done = Completer<CheckoutResult>();
  final razorpay = Razorpay();

  void finish(CheckoutResult result) {
    if (!done.isCompleted) done.complete(result);
    razorpay.clear();
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse s) {
    final paymentId = s.paymentId;
    final signature = s.signature;
    if (paymentId == null || signature == null) {
      finish(
        const CheckoutFailed(
          "The payment went through, but we couldn't read its receipt. It will show up shortly.",
        ),
      );
      return;
    }
    finish(
      CheckoutPaid(
        paymentId: paymentId,
        signature: signature,
        orderId: s.orderId ?? r.orderId,
        subscriptionId: r.subscriptionId,
      ),
    );
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse e) {
    if (e.code == Razorpay.PAYMENT_CANCELLED) {
      finish(const CheckoutCancelled());
    } else {
      finish(
        CheckoutFailed(
          (e.message?.trim().isNotEmpty ?? false)
              ? e.message!
              : "The payment didn't go through. Please try again.",
        ),
      );
    }
  });
  // a wallet app took over: Razorpay reports the result through the usual events, nothing to do here
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {});

  try {
    razorpay.open({
      'key': r.keyId,
      'name': 'GameAll',
      'description': r.description,
      if (r.orderId != null) 'order_id': r.orderId,
      if (r.subscriptionId != null) 'subscription_id': r.subscriptionId,
      if (r.amountMinor != null && r.orderId != null) 'amount': r.amountMinor,
      'currency': 'INR',
      // who is paying: with both given, Razorpay skips its "enter your mobile number / email" page and opens the payment options
      if (r.contact != null || r.email != null || r.name != null)
        'prefill': {
          'name': ?r.name,
          'contact': ?r.contact,
          'email': ?r.email,
        },
      'theme': {'color': '#7954F6'},
      // a failed attempt goes back to the app, which says so and lets the player try again: no second sheet of its own
      'retry': {'enabled': false},
      'timeout': r.timeoutSeconds,
    });
  } catch (_) {
    finish(const CheckoutFailed("We couldn't open the payment sheet."));
  }
  return done.future;
}

Future<bool> _verifyOnServer(CheckoutRequest r, CheckoutPaid paid) async {
  if (!AppConfig.isConfigured) return false;
  try {
    final res = await Supabase.instance.client.functions.invoke(
      'verify-player-payment',
      body: r.isSubscription
          ? {
              'kind': r.kind.wire,
              'id': r.itemId,
              'razorpayPaymentId': paid.paymentId,
              'razorpaySubscriptionId': paid.subscriptionId,
              'razorpaySignature': paid.signature,
            }
          : {
              'kind': 'booking',
              'bookingId': r.itemId,
              'paymentOrderId': r.paymentOrderId,
              'razorpayOrderId': paid.orderId,
              'razorpayPaymentId': paid.paymentId,
              'razorpaySignature': paid.signature,
            },
    );
    final data = res.data;
    return data is Map && data['verified'] == true;
  } catch (_) {
    // the webhook (and the check the progress page keeps making) will still record a real payment
    return false;
  }
}
