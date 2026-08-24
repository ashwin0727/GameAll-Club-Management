const PHONE_RE = /^[6-9]\d{9}$/;

export function validateGuestName(name: string): string | null {
  if (name.trim().length === 0) return "Guest name is required.";
  if (name.trim().length < 2) return "Enter at least 2 characters.";
  return null;
}

/** Phone is optional for a guest, but if given it must be a valid 10-digit Indian mobile number — the same rule and format the existing Members module uses (no country-code prefix). */
export function validateGuestPhone(phone: string | null | undefined): string | null {
  if (!phone || phone.trim() === "") return null;
  if (!PHONE_RE.test(phone.trim())) return "Enter a valid 10-digit mobile number.";
  return null;
}

export function normalizePhone(phone: string | null | undefined): string {
  return (phone ?? "").replace(/\D/g, "");
}