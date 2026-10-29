/**
 * Runs `fn` over `items` with at most `limit` running at once, and never lets one failure stop the rest.
 * Returns each item's result in order: `{ ok: true, value }` or `{ ok: false, error }`.
 *
 * Sending 200 notifications one after another is slow; sending all 200 at the same moment can overwhelm the provider.
 * A small, fixed number at a time is fast and polite.
 */
export type Settled<T> = { ok: true; value: T } | { ok: false; error: unknown };

export async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<Settled<R>[]> {
  const results: Settled<R>[] = new Array(items.length);
  let next = 0;
  async function worker(): Promise<void> {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      try {
        results[i] = { ok: true, value: await fn(items[i]!, i) };
      } catch (error) {
        results[i] = { ok: false, error };
      }
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, worker));
  return results;
}
