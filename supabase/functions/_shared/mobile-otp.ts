// Helpers for the mobile-number OTP (SMS via 2Factor.in). I/O is limited to sendSms; the rest is pure.

const encoder = new TextEncoder();

/** Last 10 digits of an Indian mobile ("+91 98765 43210" → "9876543210"), or null when it isn't a valid one. */
export function normalizeIndianMobile(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const ten = digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits.length === 11 && digits.startsWith("0") ? digits.slice(1) : digits;
  return /^[6-9]\d{9}$/.test(ten) ? ten : null;
}

/**
 * Sends [code] to [phone] through 2Factor.in's custom-OTP endpoint. Without a DLT-approved template it uses 2Factor's
 * default OTP route; set TWOFACTOR_TEMPLATE_NAME to use an approved one. The API key is part of the request path, so
 * the URL is never logged. Returns whether 2Factor accepted the message.
 */
export async function sendSms(phone: string, code: string, apiKey: string, templateName?: string): Promise<boolean> {
  const base = `https://2factor.in/API/V1/${encodeURIComponent(apiKey)}/SMS/${phone}/${code}`;
  const url = templateName ? `${base}/${encodeURIComponent(templateName)}` : base;
  try {
    const res = await fetch(url);
    const body = await res.json().catch(() => null);
    if (res.ok && body?.Status === "Success") return true;
    console.error("mobile-otp: 2factor rejected", res.status, String(body?.Details ?? "").slice(0, 120));
    return false;
  } catch {
    console.error("mobile-otp: 2factor unreachable");
    return false;
  }
}

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

export const PROOF_TTL_MINUTES = 30;

/** Keyed hash of an SMS code (kept apart from the email-code hash by a prefix). */
export function hashMobileOtp(phone: string, purpose: string, code: string, secret: string): Promise<string> {
  return hmac(secret, `mobile:${purpose}:${phone}:${code}`);
}

/**
 * Proof that [phone] passed SMS verification, for the public booking function to check. Stateless: `<expiryMs>.<hmac>`.
 * Bound to the phone and expiry, so it can't be moved to another number or extended.
 */
export async function issueMobileProof(phone: string, secret: string, now = Date.now()): Promise<string> {
  const exp = now + PROOF_TTL_MINUTES * 60_000;
  return `${exp}.${await hmac(secret, `proof:${phone}:${exp}`)}`;
}

export async function verifyMobileProof(phone: string, proof: string, secret: string, now = Date.now()): Promise<boolean> {
  const [expRaw, sig] = proof.split(".");
  const exp = Number(expRaw);
  if (!sig || !Number.isFinite(exp) || exp < now) return false;
  const expected = await hmac(secret, `proof:${phone}:${exp}`);
  if (expected.length !== sig.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0;
}
