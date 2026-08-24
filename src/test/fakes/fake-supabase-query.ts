import { vi } from "vitest";

export interface QueryResult<T> {
  data: T | null;
  error: { code: string; message: string; details?: string } | null;
}

/**
 * A minimal stand-in for a Supabase PostgREST query builder: every chainable
 * method (select/eq/order/limit/insert/update) returns itself, and it
 * resolves to `result` whether awaited directly or terminated with
 * .single()/.maybeSingle(). Good enough for asserting which filters/payload
 * a service call used, without a real HTTP round trip.
 */
export function fakeQueryBuilder<T>(result: QueryResult<T>) {
  const builder: Record<string, unknown> = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: vi.fn(() => builder),
    range: vi.fn(() => builder),
    or: vi.fn(() => builder),
    insert: vi.fn(() => builder),
    update: vi.fn(() => builder),
    maybeSingle: vi.fn(async () => result),
    single: vi.fn(async () => result),
    then: (resolve: (value: QueryResult<T>) => unknown) => Promise.resolve(result).then(resolve),
  };
  return builder;
}