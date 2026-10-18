/** The phone as stored: bare digits for +91, "+code digits" for anything else (same as the Add Member form). */
export function composePhone(countryCode: string, phone: string): string {
  const digits = phone.replace(/\D/g, "");
  return countryCode === "+91" ? digits : `${countryCode} ${digits}`;
}
