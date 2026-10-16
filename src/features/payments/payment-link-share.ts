/** Digits only; a bare 10-digit Indian mobile gets the country code WhatsApp needs. Null when it isn't a usable number. */
export function whatsappNumber(phone: string | null | undefined): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return digits;
  if (digits.length >= 11 && digits.length <= 15) return digits;
  return null;
}

/** The message staff send with the link. */
export function paymentLinkMessage(input: { guestName: string; description: string; amountLabel: string; url: string }): string {
  const name = input.guestName.trim();
  return `${name ? `Hi ${name}, ` : ""}please pay ${input.amountLabel} to confirm your booking (${input.description}): ${input.url}`;
}

/** wa.me link that opens WhatsApp with the message ready — to the guest's number when we have one, else the contact picker. */
export function whatsappShareUrl(phone: string | null | undefined, message: string): string {
  const number = whatsappNumber(phone);
  const text = encodeURIComponent(message);
  return number ? `https://wa.me/${number}?text=${text}` : `https://wa.me/?text=${text}`;
}
