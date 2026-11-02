import { assert, assertEquals } from "jsr:@std/assert@1";
import { tenDigitMobile, verifyHookSignature } from "./send-sms-hook.ts";

const secretBytes = crypto.getRandomValues(new Uint8Array(24));
const secret = `v1,whsec_${btoa(String.fromCharCode(...secretBytes))}`;

async function sign(id: string, ts: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", secretBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`)));
  return `v1,${btoa(String.fromCharCode(...sig))}`;
}

Deno.test("a correctly signed, fresh request is accepted", async () => {
  const now = Date.now();
  const ts = String(Math.floor(now / 1000));
  const body = '{"user":{"phone":"919876543210"},"sms":{"otp":"123456"}}';
  assert(await verifyHookSignature(body, { id: "msg_1", timestamp: ts, signature: await sign("msg_1", ts, body) }, secret, now));
});

Deno.test("a tampered body, a wrong secret, a missing header or a stale timestamp is refused", async () => {
  const now = Date.now();
  const ts = String(Math.floor(now / 1000));
  const body = '{"sms":{"otp":"123456"}}';
  const good = await sign("msg_1", ts, body);
  assertEquals(await verifyHookSignature(body + " ", { id: "msg_1", timestamp: ts, signature: good }, secret, now), false);
  assertEquals(await verifyHookSignature(body, { id: "msg_1", timestamp: ts, signature: good }, "v1,whsec_" + btoa("another-secret-value"), now), false);
  assertEquals(await verifyHookSignature(body, { id: null, timestamp: ts, signature: good }, secret, now), false);
  assertEquals(await verifyHookSignature(body, { id: "msg_1", timestamp: ts, signature: null }, secret, now), false);
  const old = String(Math.floor(now / 1000) - 3600);
  assertEquals(await verifyHookSignature(body, { id: "msg_1", timestamp: old, signature: await sign("msg_1", old, body) }, secret, now), false);
});

Deno.test("several signatures in the header: any valid one is enough", async () => {
  const now = Date.now();
  const ts = String(Math.floor(now / 1000));
  const body = "{}";
  assert(await verifyHookSignature(body, { id: "m", timestamp: ts, signature: `v1,AAAA ${await sign("m", ts, body)}` }, secret, now));
});

Deno.test("only Indian mobiles are accepted", () => {
  assertEquals(tenDigitMobile("919876543210"), "9876543210");
  assertEquals(tenDigitMobile("+919876543210"), "9876543210");
  assertEquals(tenDigitMobile("9876543210"), "9876543210");
  assertEquals(tenDigitMobile("14155550123"), null);
  assertEquals(tenDigitMobile("911234567890"), null); // starts with 1
  assertEquals(tenDigitMobile(""), null);
});
