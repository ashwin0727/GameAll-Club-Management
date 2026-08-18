/**
 * A single non-sensitive device flag: "someone has already signed up or signed
 * in on this browser". It only decides whether a signed-out cold start lands on
 * the Welcome pitch or straight on Login — it is never treated as authentication.
 *
 * Nothing about the account is stored here: no email, no token, no password.
 */
const ONBOARDED_KEY = "turf.device.onboarded";

function safeLocalStorage(): Storage | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    // Private-mode or blocked storage — the flow degrades to first-run.
    return null;
  }
}

export function markDeviceOnboarded(): void {
  safeLocalStorage()?.setItem(ONBOARDED_KEY, "1");
}

export function hasDeviceOnboarded(): boolean {
  return safeLocalStorage()?.getItem(ONBOARDED_KEY) === "1";
}

export function clearDeviceOnboarding(): void {
  safeLocalStorage()?.removeItem(ONBOARDED_KEY);
}