// Pure helpers for the signup email OTP — kept free of I/O so they are easy to test.

export const OTP_LENGTH = 6;
export const OTP_TTL_MINUTES = 10;
export const MAX_VERIFY_ATTEMPTS = 5;
export const RESEND_COOLDOWN_SECONDS = 30;
export const MAX_SENDS_PER_HOUR = 5;

const encoder = new TextEncoder();

/** A uniformly random 6-digit code from the OS CSPRNG (rejection sampling — no modulo bias). */
export function generateOtp(): string {
  const space = 10 ** OTP_LENGTH;
  const limit = Math.floor(0x100000000 / space) * space;
  const buf = new Uint32Array(1);
  do {
    crypto.getRandomValues(buf);
  } while (buf[0] >= limit);
  return String(buf[0] % space).padStart(OTP_LENGTH, "0");
}

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** HMAC-SHA256 over `email:code` with a server-only secret, so a leaked table row can't be brute-forced offline. */
export async function hashOtp(email: string, code: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(`${email.toLowerCase()}:${code}`)));
}

/** Constant-time string comparison. */
export function safeEqual(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** The "One Time Password" email — GameAll branding only. */
export function buildOtpEmail(opts: { name: string; code: string; logoUrl: string }): { subject: string; html: string; text: string } {
  const first = opts.name.trim().split(/\s+/)[0] || "there";
  const name = escapeHtml(first);
  const spaced = opts.code.split("").join(" ");
  const subject = `${opts.code} is your GameAll verification code`;
  const html = `<!doctype html>
<html lang="en">
<body style="margin:0;padding:0;background:#f3f5f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f172a;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your GameAll one time password is ${opts.code}. It expires in ${OTP_TTL_MINUTES} minutes.</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f5f8;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e9f0;">
        <tr><td align="center" style="padding:32px 24px 8px;">
          <img src="${escapeHtml(opts.logoUrl)}" alt="GameAll" width="56" height="56" style="display:block;border:0;border-radius:12px;">
          <div style="margin-top:12px;font-size:22px;font-weight:800;letter-spacing:.2px;color:#0f172a;">GameAll</div>
        </td></tr>
        <tr><td style="padding:16px 32px 8px;">
          <h1 style="margin:0 0 8px;font-size:20px;line-height:28px;">One Time Password</h1>
          <p style="margin:0;font-size:15px;line-height:24px;color:#475569;">Hi ${name}, use the code below to verify your email address and finish creating your GameAll account.</p>
        </td></tr>
        <tr><td align="center" style="padding:20px 32px;">
          <div style="display:inline-block;padding:16px 28px;border-radius:12px;background:#ecfdf5;border:1px solid #a7f3d0;font-size:34px;font-weight:800;letter-spacing:6px;color:#047857;font-family:'SF Mono',Menlo,Consolas,monospace;">${spaced}</div>
        </td></tr>
        <tr><td style="padding:0 32px 28px;">
          <p style="margin:0 0 12px;font-size:14px;line-height:22px;color:#475569;">This code expires in <strong>${OTP_TTL_MINUTES} minutes</strong> and can be used once.</p>
          <p style="margin:0;font-size:13px;line-height:20px;color:#94a3b8;">For your security, never share this code with anyone — GameAll will never ask for it. If you didn't try to create an account, you can safely ignore this email.</p>
        </td></tr>
        <tr><td style="padding:16px 32px;background:#f8fafc;border-top:1px solid #e5e9f0;font-size:12px;color:#94a3b8;" align="center">&copy; ${new Date().getFullYear()} GameAll. All rights reserved.</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  const text = `GameAll — One Time Password\n\nHi ${first}, your verification code is ${opts.code}.\nIt expires in ${OTP_TTL_MINUTES} minutes and can be used once.\n\nNever share this code with anyone. If you didn't try to create an account, ignore this email.`;
  return { subject, html, text };
}
