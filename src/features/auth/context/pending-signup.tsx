"use client";

import * as React from "react";

interface PendingSignup {
  name: string;
  email: string;
  /**
   * Held in React state for the length of the visit and nothing more — never
   * written to localStorage, sessionStorage, a cookie or a URL. It exists so
   * "Change email address" can re-issue the signup against the corrected
   * address without asking the user to type everything again. A page reload
   * clears it, and that path falls back to sending them through signup.
   */
  password: string;
}

interface PendingSignupContextValue {
  pending: PendingSignup | null;
  setPending: (value: PendingSignup) => void;
  clearPending: () => void;
}

const PendingSignupContext = React.createContext<PendingSignupContextValue | null>(null);

/**
 * Lives in the auth route-group layout, so it survives client navigation from
 * /signup to /verify-email while staying out of the authenticated app entirely.
 */
export function PendingSignupProvider({ children }: { children: React.ReactNode }) {
  const [pending, setPendingState] = React.useState<PendingSignup | null>(null);

  const value = React.useMemo<PendingSignupContextValue>(
    () => ({
      pending,
      setPending: setPendingState,
      clearPending: () => setPendingState(null),
    }),
    [pending],
  );

  return <PendingSignupContext.Provider value={value}>{children}</PendingSignupContext.Provider>;
}

export function usePendingSignup(): PendingSignupContextValue {
  const context = React.useContext(PendingSignupContext);
  if (!context) {
    throw new Error("usePendingSignup must be used inside PendingSignupProvider");
  }
  return context;
}