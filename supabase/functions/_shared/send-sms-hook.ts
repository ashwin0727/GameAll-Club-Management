// Helpers for Supabase Auth's "Send SMS" hook (the Player app's phone login). Pure except sendVoiceOtp / sendTextOtp.

const encoder = new TextEncoder();

function fromBase64(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function toBase64(bytes: ArrayBuffer): string {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s);
}

/**
 * Checks the Standard Webhooks signature Supabase puts on every hook call (headers webhook-id, webhook-timestamp,
 * webhook-signature). [secret] is the value shown in the dashboard, "v1,whsec_<base64>". The call is refused when the
 * signature does not match, or when its timestamp is more than [toleranceSeconds] from now (a replayed request).
 */
export async function verifyHookSignature(
  rawBody: string,
  headers: { id: string | null; timestamp: string | null; signature: string | null },
  secret: string,
  nowMs = Date.now(),
  toleranceSeconds = 300,
): Promise<boolean> {
  const { id, timestamp, signature } = headers;
  if (!id || !timestamp || !signature) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowMs / 1000 - ts) > toleranceSeconds) return false;
  const keyB64 = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  let keyBytes: Uint8Array<ArrayBuffer>;
  try {
    keyBytes = fromBase64(keyB64);
  } catch {
    return false;
  }
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = toBase64(await crypto.subtle.sign("HMAC", key, encoder.encode(`${id}.${timestamp}.${rawBody}`)));
  // The header can carry several space-separated signatures ("v1,<sig> v1,<sig>"): any one may match.
  for (const part of signature.split(" ")) {
    const [version, sig] = part.split(",");
    if (version !== "v1" || !sig || sig.length !== expected.length) continue;
    let diff = 0;
    for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
    if (diff === 0) return true;
  }
  return false;
}

/** The ten-digit Indian mobile in a hook payload's phone ("919876543210", "+919876543210"), or null. */
export function tenDigitMobile(phone: string): string | null {
  const digits = phone.replace(/\D/g, "");
  const ten = digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits.length === 10 ? digits : "";
  return /^[6-9]\d{9}$/.test(ten) ? ten : null;
}

/**
 * Reads the code out loud by phone call (2Factor.in's voice OTP). This route needs no DLT registration, which is why the Player
 * app uses it until text messages are approved. The API key is part of the request path, so the URL is never logged.
 */
export async function sendVoiceOtp(phone: string, code: string, apiKey: string): Promise<boolean> {
  return callTwoFactor(`https://2factor.in/API/V1/${encodeURIComponent(apiKey)}/VOICE/${phone}/${code}`);
}

/** Sends the code as a text message (2Factor's default OTP route, or a DLT-approved template). */
export async function sendTextOtp(phone: string, code: string, apiKey: string, templateName?: string): Promise<boolean> {
  const base = `https://2factor.in/API/V1/${encodeURIComponent(apiKey)}/SMS/${phone}/${code}`;
  return callTwoFactor(templateName ? `${base}/${encodeURIComponent(templateName)}` : base);
}

async function callTwoFactor(url: string): Promise<boolean> {
  try {
    const res = await fetch(url);
    const body = await res.json().catch(() => null);
    if (res.ok && body?.Status === "Success") return true;
    console.error("send-sms-otp: 2factor rejected", res.status, String(body?.Details ?? "").slice(0, 120));
    return false;
  } catch {
    console.error("send-sms-otp: 2factor unreachable");
    return false;
  }
}
