import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/types/database.types";
import { createResilientFetch } from "@/lib/supabase/resilient-fetch";

type BrowserClient = ReturnType<typeof createBrowserClient<Database>>;
let browserClient: BrowserClient | undefined;

export function createClient(): BrowserClient {
  if (typeof window !== "undefined" && browserClient) return browserClient;
  // On a 401 the sign-in is renewed and the request tried again (a visitor with a wrong clock never renews it on their own).
  const fetchWithRenewal = createResilientFetch(undefined, undefined, async () => {
    const { data, error } = await browserClient!.auth.refreshSession();
    return error ? null : (data.session?.access_token ?? null);
  });
  browserClient = createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { global: { fetch: fetchWithRenewal } },
  );
  return browserClient;
}