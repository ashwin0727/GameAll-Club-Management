/** Banks offered in the payout form's dropdown, and the IFSC helpers around it. */

export const INDIAN_BANKS = [
  "State Bank of India",
  "HDFC Bank",
  "ICICI Bank",
  "Axis Bank",
  "Kotak Mahindra Bank",
  "Punjab National Bank",
  "Bank of Baroda",
  "Canara Bank",
  "Union Bank of India",
  "Bank of India",
  "Indian Bank",
  "Central Bank of India",
  "Indian Overseas Bank",
  "UCO Bank",
  "Bank of Maharashtra",
  "Punjab & Sind Bank",
  "IDFC FIRST Bank",
  "IndusInd Bank",
  "Yes Bank",
  "Federal Bank",
  "South Indian Bank",
  "Karnataka Bank",
  "Karur Vysya Bank",
  "City Union Bank",
  "RBL Bank",
  "Bandhan Bank",
  "IDBI Bank",
  "AU Small Finance Bank",
  "Equitas Small Finance Bank",
  "Ujjivan Small Finance Bank",
  "Jammu & Kashmir Bank",
  "DCB Bank",
  "Tamilnad Mercantile Bank",
  "Saraswat Co-operative Bank",
  "Paytm Payments Bank",
  "Airtel Payments Bank",
  "India Post Payments Bank",
  "Standard Chartered Bank",
  "HSBC",
  "Citibank",
  "Deutsche Bank",
] as const;

/** The first four letters of an IFSC identify the bank. */
const IFSC_PREFIX: Record<string, string> = {
  SBIN: "State Bank of India",
  HDFC: "HDFC Bank",
  ICIC: "ICICI Bank",
  UTIB: "Axis Bank",
  KKBK: "Kotak Mahindra Bank",
  PUNB: "Punjab National Bank",
  BARB: "Bank of Baroda",
  CNRB: "Canara Bank",
  UBIN: "Union Bank of India",
  BKID: "Bank of India",
  IDIB: "Indian Bank",
  CBIN: "Central Bank of India",
  IOBA: "Indian Overseas Bank",
  UCBA: "UCO Bank",
  MAHB: "Bank of Maharashtra",
  PSIB: "Punjab & Sind Bank",
  IDFB: "IDFC FIRST Bank",
  INDB: "IndusInd Bank",
  YESB: "Yes Bank",
  FDRL: "Federal Bank",
  SIBL: "South Indian Bank",
  KARB: "Karnataka Bank",
  KVBL: "Karur Vysya Bank",
  CIUB: "City Union Bank",
  RATN: "RBL Bank",
  BDBL: "Bandhan Bank",
  IBKL: "IDBI Bank",
  AUBL: "AU Small Finance Bank",
  ESFB: "Equitas Small Finance Bank",
  USFB: "Ujjivan Small Finance Bank",
  JAKA: "Jammu & Kashmir Bank",
  DCBL: "DCB Bank",
  TMBL: "Tamilnad Mercantile Bank",
  PYTM: "Paytm Payments Bank",
  AIRP: "Airtel Payments Bank",
  IPOS: "India Post Payments Bank",
  SCBL: "Standard Chartered Bank",
  HSBC: "HSBC",
  CITI: "Citibank",
  DEUT: "Deutsche Bank",
};

export const IFSC_PATTERN = /^[A-Z]{4}0[A-Z0-9]{6}$/;

/** The bank an IFSC belongs to, from its first four letters, when we know it. */
export function bankFromIfsc(ifsc: string): string | null {
  return IFSC_PREFIX[ifsc.trim().toUpperCase().slice(0, 4)] ?? null;
}

export interface IfscDetails {
  bank: string;
  branch: string;
  city: string;
}

/**
 * Looks an IFSC up in the public RBI-sourced directory (ifsc.razorpay.com). Returns null when the code does not exist; throws when the
 * directory cannot be reached, so the caller can say "try again" instead of "not found".
 */
export async function lookupIfsc(code: string, signal?: AbortSignal): Promise<IfscDetails | null> {
  const ifsc = code.trim().toUpperCase();
  if (!IFSC_PATTERN.test(ifsc)) return null;
  const res = await fetch(`https://ifsc.razorpay.com/${ifsc}`, { signal, headers: { Accept: "application/json" } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error("The IFSC directory is not available right now.");
  const j = (await res.json()) as { BANK?: string; BRANCH?: string; CITY?: string };
  if (!j.BANK) return null;
  return { bank: bankFromIfsc(ifsc) ?? j.BANK, branch: j.BRANCH ?? "", city: j.CITY ?? "" };
}
