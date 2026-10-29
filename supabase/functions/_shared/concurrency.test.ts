import { assertEquals } from "jsr:@std/assert@1";
import { mapLimit } from "./concurrency.ts";

Deno.test("mapLimit returns every result in order", async () => {
  const out = await mapLimit([1, 2, 3, 4, 5], 2, (n) => Promise.resolve(n * 10));
  assertEquals(out.map((r) => (r.ok ? r.value : -1)), [10, 20, 30, 40, 50]);
});

Deno.test("mapLimit never runs more than the limit at once", async () => {
  let running = 0;
  let peak = 0;
  await mapLimit(Array.from({ length: 20 }, (_, i) => i), 4, async () => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((r) => setTimeout(r, 5));
    running--;
  });
  assertEquals(peak <= 4, true);
  assertEquals(peak > 1, true);
});

Deno.test("mapLimit isolates failures", async () => {
  const out = await mapLimit([1, 2, 3], 3, (n) => (n === 2 ? Promise.reject(new Error("boom")) : Promise.resolve(n)));
  assertEquals(out.map((r) => r.ok), [true, false, true]);
});

Deno.test("mapLimit handles an empty list", async () => {
  assertEquals(await mapLimit([], 5, () => Promise.resolve(1)), []);
});
