/**
 * When to try a failed query again. A database or permission error (an SQLSTATE code such as 42501, or an HTTP 4xx) will fail the same
 * way every time, so repeating it only doubles the load. A dropped connection or a busy server can recover, so those get one more try.
 * (The Supabase client already retries safe reads itself; this covers whatever slipped through.)
 */
export function shouldRetryQuery(failureCount: number, error: unknown): boolean {
  if (failureCount >= 1) return false;
  const e = error as { code?: unknown; status?: unknown; statusCode?: unknown } | null;
  const status = Number(e?.status ?? e?.statusCode);
  if (Number.isFinite(status) && status >= 400 && status < 500 && status !== 408 && status !== 429) return false;
  if (typeof e?.code === "string" && /^[0-9A-Z]{5}$/.test(e.code)) return false;
  return true;
}

/** Wait a little longer each time, with a random pause so many screens do not retry in step. */
export function queryRetryDelay(attempt: number): number {
  return Math.min(1_000 * 2 ** attempt, 8_000) + Math.random() * 300;
}
