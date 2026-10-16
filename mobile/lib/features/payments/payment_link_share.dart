// Sharing a guest booking's payment link — pure helpers (same rules as the web's payment-link-share.ts) so the
// WhatsApp number and message are tested rather than eyeballed.

/// Digits only; a bare 10-digit Indian mobile gets the country code WhatsApp needs. Null when unusable.
String? whatsappNumber(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return digits;
  if (digits.length >= 11 && digits.length <= 15) return digits;
  return null;
}

/// The message staff send with the link.
String paymentLinkMessage({required String guestName, required String description, required String amountLabel, required String url}) {
  final name = guestName.trim();
  return '${name.isEmpty ? '' : 'Hi $name, '}please pay $amountLabel to confirm your booking ($description): $url';
}

/// wa.me link that opens WhatsApp with the message ready — to the guest's number when we have one.
Uri whatsappShareUri(String? phone, String message) {
  final number = whatsappNumber(phone);
  return Uri.parse('https://wa.me/${number ?? ''}?text=${Uri.encodeComponent(message)}');
}
