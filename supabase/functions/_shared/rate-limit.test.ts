import { assertEquals } from "jsr:@std/assert";
import { allowed } from "./rate-limit.ts";

// deno-lint-ignore no-explicit-any
const fake = (result: { data?: unknown; error?: { message: string } | null }, throws = false): any => ({
  rpc: () => (throws ? Promise.reject(new Error("down")) : Promise.resolve({ data: result.data ?? null, error: result.error ?? null })),
});

Deno.test("allowed passes the limiter's answer through", async () => {
  assertEquals(await allowed(fake({ data: true }), "b", 3), true);
  assertEquals(await allowed(fake({ data: false }), "b", 3), false);
});

Deno.test("allowed fails open when the limiter errors or is unreachable", async () => {
  assertEquals(await allowed(fake({ error: { message: "boom" } }), "b", 3), true);
  assertEquals(await allowed(fake({}, true), "b", 3), true);
});
