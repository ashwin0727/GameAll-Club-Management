import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createResilientFetch, isSafeToRetry } from "@/lib/supabase/resilient-fetch";

const url = (path: string) => `https://x.supabase.co${path}`;

describe("isSafeToRetry", () => {
  it("allows GET and HEAD", () => {
    expect(isSafeToRetry(url("/rest/v1/courts?select=*"), { method: "GET" })).toBe(true);
    expect(isSafeToRetry(url("/rest/v1/courts"), { method: "HEAD" })).toBe(true);
    expect(isSafeToRetry(url("/rest/v1/courts"))).toBe(true);
  });

  it("allows POSTs only to read-only database functions", () => {
    for (const fn of ["list_coaching_sessions", "get_session_bundle", "my_facility_plan", "period_revenue_inr", "admin_list_facilities"]) {
      expect(isSafeToRetry(url(`/rest/v1/rpc/${fn}`), { method: "POST" })).toBe(true);
    }
  });

  it("never retries anything that writes", () => {
    for (const fn of ["create_booking", "record_membership_payment", "admin_mark_settled", "select_facility_plan", "mark_notifications_read"]) {
      expect(isSafeToRetry(url(`/rest/v1/rpc/${fn}`), { method: "POST" })).toBe(false);
    }
    expect(isSafeToRetry(url("/rest/v1/payments"), { method: "POST" })).toBe(false);
    expect(isSafeToRetry(url("/rest/v1/bookings?id=eq.1"), { method: "PATCH" })).toBe(false);
    expect(isSafeToRetry(url("/rest/v1/bookings?id=eq.1"), { method: "DELETE" })).toBe(false);
    expect(isSafeToRetry(url("/auth/v1/token?grant_type=password"), { method: "POST" })).toBe(false);
    expect(isSafeToRetry(url("/functions/v1/delete-account"), { method: "POST" })).toBe(false);
  });
});

describe("createResilientFetch", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const ok = () => new Response("{}", { status: 200 });
  const status = (code: number, headers?: Record<string, string>) => new Response("", { status: code, headers });

  it("retries a busy server on a read and returns the first good answer", async () => {
    const base = vi.fn().mockResolvedValueOnce(status(503)).mockResolvedValueOnce(status(429, { "retry-after": "1" })).mockResolvedValueOnce(ok());
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/courts"));
    await vi.runAllTimersAsync();
    expect((await promise).status).toBe(200);
    expect(base).toHaveBeenCalledTimes(3);
  });

  it("retries a dropped connection on a read", async () => {
    const base = vi.fn().mockRejectedValueOnce(new TypeError("fetch failed")).mockResolvedValueOnce(ok());
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/rpc/list_roles"), { method: "POST", body: "{}" });
    await vi.runAllTimersAsync();
    expect((await promise).status).toBe(200);
    expect(base).toHaveBeenCalledTimes(2);
  });

  it("stops after three attempts and returns the last response", async () => {
    const base = vi.fn().mockResolvedValue(status(503));
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/courts"));
    await vi.runAllTimersAsync();
    expect((await promise).status).toBe(503);
    expect(base).toHaveBeenCalledTimes(3);
  });

  it("sends a write exactly once, even when the server answers 503", async () => {
    const base = vi.fn().mockResolvedValue(status(503));
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/rpc/create_booking"), { method: "POST", body: "{}" });
    await vi.runAllTimersAsync();
    expect((await promise).status).toBe(503);
    expect(base).toHaveBeenCalledTimes(1);
  });

  it("does not retry a write whose connection dropped", async () => {
    const base = vi.fn().mockRejectedValue(new TypeError("fetch failed"));
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/payments"), { method: "POST", body: "{}" }).catch((e: Error) => e);
    await vi.runAllTimersAsync();
    expect(await promise).toBeInstanceOf(TypeError);
    expect(base).toHaveBeenCalledTimes(1);
  });

  it("does not retry client errors", async () => {
    const base = vi.fn().mockResolvedValue(status(403));
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/rpc/list_coaching_sessions"), { method: "POST", body: "{}" });
    await vi.runAllTimersAsync();
    expect((await promise).status).toBe(403);
    expect(base).toHaveBeenCalledTimes(1);
  });

  it("gives up when a request hangs past the timeout", async () => {
    const base = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_, reject) => init?.signal?.addEventListener("abort", () => reject(init.signal?.reason))));
    const f = createResilientFetch(base as unknown as typeof fetch, 1_000);
    const promise = f(url("/rest/v1/rpc/create_booking"), { method: "POST", body: "{}" }).catch((e: Error) => e);
    await vi.advanceTimersByTimeAsync(1_500);
    const error = await promise;
    expect((error as Error).name).toBe("TimeoutError");
    expect(base).toHaveBeenCalledTimes(1);
  });

  it("does not retry when the caller cancels", async () => {
    const controller = new AbortController();
    const base = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_, reject) => init?.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")))));
    const f = createResilientFetch(base as unknown as typeof fetch);
    const promise = f(url("/rest/v1/courts"), { signal: controller.signal }).catch((e: Error) => e);
    controller.abort();
    await vi.runAllTimersAsync();
    expect(((await promise) as Error).name).toBe("AbortError");
    expect(base).toHaveBeenCalledTimes(1);
  });
});

describe("expired sign-in", () => {
  const expired = () => new Response('{"code":"PGRST303","message":"JWT expired"}', { status: 401 });
  const auth = (init?: RequestInit) => new Headers(init?.headers).get("authorization");
  const withOld = (extra: RequestInit = {}): RequestInit => ({ ...extra, headers: { Authorization: "Bearer old" } });

  it("renews the token and repeats the request with it", async () => {
    const base = vi.fn(async (_i: RequestInfo | URL, init?: RequestInit) => (auth(init) === "Bearer new" ? new Response("[]", { status: 200 }) : expired()));
    const refresh = vi.fn(async () => "new");
    const f = createResilientFetch(base as unknown as typeof fetch, 5000, refresh);
    const res = await f(url("/rest/v1/courts"), withOld());
    expect(res.status).toBe(200);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(base.mock.calls.map((c) => auth(c[1]))).toEqual(["Bearer old", "Bearer new"]);
  });

  it("sends a write again with the new token (the server refused it before doing anything)", async () => {
    const base = vi.fn(async (_i: RequestInfo | URL, init?: RequestInit) => (auth(init) === "Bearer new" ? new Response("{}", { status: 201 }) : expired()));
    const f = createResilientFetch(base as unknown as typeof fetch, 5000, async () => "new");
    const res = await f(url("/rest/v1/rpc/create_booking"), withOld({ method: "POST", body: '{"a":1}' }));
    expect(res.status).toBe(201);
    expect(base).toHaveBeenCalledTimes(2);
    expect(base.mock.calls.map((c) => c[1]?.body)).toEqual(['{"a":1}', '{"a":1}']);
  });

  it("renews only once per request, even if the new token is refused too", async () => {
    const base = vi.fn(async () => expired());
    const refresh = vi.fn(async () => "new");
    const f = createResilientFetch(base as unknown as typeof fetch, 5000, refresh);
    expect((await f(url("/rest/v1/courts"), withOld())).status).toBe(401);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(base).toHaveBeenCalledTimes(2);
  });

  it("returns the original answer when the token cannot be renewed", async () => {
    const f = createResilientFetch((async () => expired()) as unknown as typeof fetch, 5000, async () => null);
    const res = await f(url("/rest/v1/courts"), withOld());
    expect(res.status).toBe(401);
    expect(await res.text()).toContain("JWT expired");
  });

  it("never renews for sign-in calls", async () => {
    const refresh = vi.fn(async () => "x");
    const f = createResilientFetch((async () => new Response("", { status: 401 })) as unknown as typeof fetch, 5000, refresh);
    expect((await f(url("/auth/v1/token?grant_type=refresh_token"), { method: "POST", body: "{}" })).status).toBe(401);
    expect(refresh).not.toHaveBeenCalled();
  });

  it("requests that fail together share one renewal", async () => {
    const base = vi.fn(async (_i: RequestInfo | URL, init?: RequestInit) => (auth(init) === "Bearer new" ? new Response("[]", { status: 200 }) : expired()));
    const refresh = vi.fn(() => new Promise<string>((resolve) => setTimeout(() => resolve("new"), 20)));
    const f = createResilientFetch(base as unknown as typeof fetch, 5000, refresh);
    const results = await Promise.all(["courts", "sports", "members"].map((t) => f(url(`/rest/v1/${t}`), withOld())));
    expect(results.map((r) => r.status)).toEqual([200, 200, 200]);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("without a renew callback a 401 is simply returned", async () => {
    const f = createResilientFetch((async () => expired()) as unknown as typeof fetch, 5000);
    expect((await f(url("/rest/v1/courts"), withOld())).status).toBe(401);
  });
});
