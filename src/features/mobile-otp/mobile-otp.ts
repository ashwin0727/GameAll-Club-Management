import { createClient } from "@/lib/supabase/client";

export type MobileOtpPurpose = "signup" | "booking";

/** The 10-digit Indian mobile inside whatever the user typed ("+91 98765 43210" → "9876543210"), or null. */
export function tenDigitMobile(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  const ten = digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits.length === 11 && digits.startsWith("0") ? digits.slice(1) : digits;
  return /^[6-9]\d{9}$/.test(ten) ? ten : null;
}

async function call(body: Record<string, unknown>): Promise<{ proof?: string }> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke<{ ok?: boolean; proof?: string }>("mobile-otp", { body });
  if (!error) return { proof: data?.proof };
  let message = "Something went wrong. Please try again.";
  const context = (error as { context?: Response }).context;
  if (context && typeof context.json === "function") {
    try {
      message = ((await context.json()) as { message?: string }).message ?? message;
    } catch {
      /* keep the generic message */
    }
  } else if (/fetch|network/i.test(error.message ?? "")) {
    message = "Network error. Check your connection and try again.";
  }
  throw new Error(message);
}

/** Texts a 6-digit code to the number. */
export async function sendMobileOtp(phone: string, purpose: MobileOtpPurpose): Promise<void> {
  await call({ action: "send", phone, purpose });
}

/** Checks the code. For `booking`, resolves with the signed proof the booking function requires. */
export async function verifyMobileOtp(phone: string, code: string, purpose: MobileOtpPurpose): Promise<string | undefined> {
  return (await call({ action: "verify", phone, code, purpose })).proof;
}
