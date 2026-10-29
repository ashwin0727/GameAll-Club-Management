/**
 * A fetch for the Supabase clients that survives the usual hiccups under load: a dropped connection, a busy server (429 / 502 /
 * 503 / 504), a request that hangs.
 *
 * Only requests that are safe to repeat are retried:
 *   • GET / HEAD, and
 *   • POSTs to read-only database functions (list_*, get_*, my_*, ... see READ_RPC), which only read.
 * Anything that writes (inserts, updates, payments, bookings, sign-in) is sent exactly once, so a slow response can never create a
 * duplicate. Writes still get the timeout, so they cannot hang forever.
 *
 * Retries wait 0.3 s, 0.6 s, 1.2 s plus a random pause (so many clients do not retry in step), and honour a Retry-After header.
 */

const RETRYABLE_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);
const MAX_ATTEMPTS = 3;
const BASE_DELAY_MS = 300;
const MAX_RETRY_AFTER_MS = 5_000;
export const REQUEST_TIMEOUT_MS = 30_000;

/** Database functions that only read. A POST to one of these can be repeated safely. */
const READ_RPC = /^(list_|get_|my_|count_|search_|period_|is_|admin_list_|admin_get_|plan_has_|plan_includes_|public_facility_accepts_|effective_)/;

function requestUrl(input: RequestInfo | URL): string {
  return typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
}

function requestMethod(input: RequestInfo | URL, init?: RequestInit): string {
  return (init?.method ?? (typeof input === "object" && "method" in input ? input.method : "GET")).toUpperCase();
}

/** Whether repeating this request cannot change anything. */
export function isSafeToRetry(input: RequestInfo | URL, init?: RequestInit): boolean {
  const method = requestMethod(input, init);
  const url = requestUrl(input);
  if (method === "GET" || method === "HEAD") return true;
  if (method === "POST") {
    const rpc = url.match(/\/rest\/v1\/rpc\/([a-z0-9_]+)/i);
    return rpc !== null && READ_RPC.test(rpc[1]!);
  }
  return false;
}

function retryDelay(attempt: number, response?: Response): number {
  const retryAfter = response?.headers.get("retry-after");
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, MAX_RETRY_AFTER_MS);
  }
  return BASE_DELAY_MS * 2 ** attempt + Math.random() * 250;
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** One attempt, cut short after the timeout (or sooner if the caller aborts). */
async function attemptOnce(base: typeof fetch, input: RequestInfo | URL, init: RequestInit | undefined, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const callerSignal = init?.signal;
  const onCallerAbort = () => controller.abort(callerSignal?.reason);
  if (callerSignal?.aborted) controller.abort(callerSignal.reason);
  else callerSignal?.addEventListener("abort", onCallerAbort, { once: true });
  const timer = setTimeout(() => controller.abort(new DOMException("The request timed out.", "TimeoutError")), timeoutMs);
  try {
    return await base(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
    callerSignal?.removeEventListener("abort", onCallerAbort);
  }
}

export function createResilientFetch(base: typeof fetch = (...args) => fetch(...args), timeoutMs = REQUEST_TIMEOUT_MS): typeof fetch {
  return async (input, init) => {
    const retryable = isSafeToRetry(input, init);
    const attempts = retryable ? MAX_ATTEMPTS : 1;
    for (let attempt = 0; ; attempt++) {
      try {
        const response = await attemptOnce(base, input, init, timeoutMs);
        if (!retryable || attempt >= attempts - 1 || !RETRYABLE_STATUS.has(response.status)) return response;
        await sleep(retryDelay(attempt, response));
      } catch (error) {
        // The caller gave up on purpose: never retry that.
        if (init?.signal?.aborted || attempt >= attempts - 1) throw error;
        await sleep(retryDelay(attempt));
      }
    }
  };
}

export const resilientFetch: typeof fetch = createResilientFetch();
