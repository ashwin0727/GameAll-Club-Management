import { z } from "zod";

const name = z.string().trim().min(2, "Enter the account holder's name.").max(80);

export const bankPayoutSchema = z.object({
  type: z.literal("BANK"),
  accountHolderName: name,
  bankName: z.string().trim().min(2, "Enter the bank's name.").max(80),
  accountNumber: z
    .string()
    .trim()
    .regex(/^\d{9,18}$/, "Account numbers are 9 to 18 digits."),
  ifsc: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{4}0[A-Z0-9]{6}$/, "Enter a valid IFSC, like HDFC0001234."),
});

export const upiPayoutSchema = z.object({
  type: z.literal("UPI"),
  accountHolderName: name,
  upiId: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9.\-_]{2,256}@[a-z][a-z0-9]{1,63}$/, "Enter a valid UPI ID, like name@bank."),
});

export const payoutSchema = z.discriminatedUnion("type", [bankPayoutSchema, upiPayoutSchema]);

/** "XXXXXX1234" — enough to recognise an account, never the whole number. */
export function maskAccountNumber(n: string | null): string {
  if (!n) return "";
  return n.length <= 4 ? n : `${"X".repeat(n.length - 4)}${n.slice(-4)}`;
}

/** "ra••••@okhdfc" — keeps the handle's first two characters and the bank. */
export function maskUpi(upi: string | null): string {
  if (!upi) return "";
  const [handle = "", bank = ""] = upi.split("@");
  return `${handle.slice(0, 2)}${"•".repeat(Math.max(handle.length - 2, 2))}@${bank}`;
}
