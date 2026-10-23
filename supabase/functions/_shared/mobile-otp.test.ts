import { assert, assertEquals } from "jsr:@std/assert@1";
import { hashMobileOtp, issueMobileProof, normalizeIndianMobile, verifyMobileProof } from "./mobile-otp.ts";

Deno.test("normalizeIndianMobile accepts common formats and rejects bad numbers", () => {
  assertEquals(normalizeIndianMobile("98765 43210"), "9876543210");
  assertEquals(normalizeIndianMobile("+91 98765-43210"), "9876543210");
  assertEquals(normalizeIndianMobile("09876543210"), "9876543210");
  assertEquals(normalizeIndianMobile("1234567890"), null); // must start 6-9
  assertEquals(normalizeIndianMobile("98765"), null);
  assertEquals(normalizeIndianMobile(""), null);
});

Deno.test("hashMobileOtp depends on phone, purpose, code and secret", async () => {
  const a = await hashMobileOtp("9876543210", "signup", "123456", "s");
  assertEquals(a, await hashMobileOtp("9876543210", "signup", "123456", "s"));
  assert(a !== (await hashMobileOtp("9876543210", "booking", "123456", "s")));
  assert(a !== (await hashMobileOtp("9876543211", "signup", "123456", "s")));
});

Deno.test("mobile proof verifies for its phone only, and expires", async () => {
  const now = 1_000_000;
  const proof = await issueMobileProof("9876543210", "secret", now);
  assert(await verifyMobileProof("9876543210", proof, "secret", now + 1000));
  assert(!(await verifyMobileProof("9876543211", proof, "secret", now + 1000)));
  assert(!(await verifyMobileProof("9876543210", proof, "other", now + 1000)));
  assert(!(await verifyMobileProof("9876543210", proof, "secret", now + 31 * 60_000)));
  assert(!(await verifyMobileProof("9876543210", "garbage", "secret", now)));
});
