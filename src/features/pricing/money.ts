/**
 * Every currency this app supports today has 2 minor-unit decimal places
 * (paise, cents). Kept as a lookup (not a hard-coded "/100" everywhere) so a
 * zero-decimal currency (e.g. JPY) can be added later without touching call sites.
 */
const MINOR_UNIT_EXPONENT: Record<string, number> = { INR: 2, USD: 2, GBP: 2 };

const CURRENCY_SYMBOL: Record<string, string> = { INR: "₹", USD: "$", GBP: "£" };

function exponentFor(currency: string): number {
  return MINOR_UNIT_EXPONENT[currency] ?? 2;
}

/** "400" or "400.50" (major units, as typed by the owner) -> integer minor units. Never uses float math for the result. */
export function toMinorUnits(amount: string | number, currency: string): number {
  const exponent = exponentFor(currency);
  const str = typeof amount === "number" ? amount.toString() : amount.trim();
  const [wholeRaw, fractionRaw = ""] = str.split(".");
  const whole = wholeRaw === "" || wholeRaw === undefined ? "0" : wholeRaw;
  const fraction = fractionRaw.padEnd(exponent, "0").slice(0, exponent);
  const sign = whole.startsWith("-") ? -1 : 1;
  const digits = `${whole.replace("-", "")}${fraction}`;
  return sign * Number.parseInt(digits || "0", 10);
}

/** Integer minor units -> major-unit numeric value, e.g. 40000 -> 400. */
export function fromMinorUnits(amountMinor: number, currency: string): number {
  const exponent = exponentFor(currency);
  return amountMinor / 10 ** exponent;
}

/** 40000, "INR" -> "₹400.00" (or "₹400" when the amount is whole, for a cleaner default onboarding display). */
export function formatCurrency(amountMinor: number, currency: string): string {
  const major = fromMinorUnits(amountMinor, currency);
  const symbol = CURRENCY_SYMBOL[currency] ?? `${currency} `;
  const isWhole = Number.isInteger(major);
  const formatted = major.toLocaleString("en-IN", {
    minimumFractionDigits: isWhole ? 0 : 2,
    maximumFractionDigits: 2,
  });
  return `${symbol}${formatted}`;
}

export const PRICING_UNIT_LABEL: Record<string, string> = {
  PER_HOUR: "/ hour",
  PER_30_MINUTES: "/ 30 min",
  PER_SESSION: "/ session",
  PER_MATCH: "/ match",
};