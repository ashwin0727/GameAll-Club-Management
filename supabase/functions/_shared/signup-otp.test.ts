import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { buildOtpEmail, generateOtp, hashOtp, OTP_LENGTH, safeEqual } from "./signup-otp.ts";

Deno.test("generateOtp returns a zero-padded 6-digit numeric string", () => {
  for (let i = 0; i < 200; i++) assert(new RegExp(`^\\d{${OTP_LENGTH}}$`).test(generateOtp()));
});

Deno.test("hashOtp is deterministic, case-insensitive on email, and depends on code and secret", async () => {
  const a = await hashOtp("A@x.com", "123456", "s");
  assertEquals(a, await hashOtp("a@x.com", "123456", "s"));
  assertNotEquals(a, await hashOtp("a@x.com", "123457", "s"));
  assertNotEquals(a, await hashOtp("a@x.com", "123456", "other"));
});

Deno.test("safeEqual compares exactly", () => {
  assert(safeEqual("abc", "abc"));
  assert(!safeEqual("abc", "abd"));
  assert(!safeEqual("abc", "abcd"));
});

Deno.test("OTP email is GameAll-branded, shows the code and logo, never 'Club Management'", () => {
  const { html, text, subject } = buildOtpEmail({ name: "Ravi <b>", code: "042917", logoUrl: "https://app.gameall.in/logo-icon.png" });
  assert(html.includes("0 4 2 9 1 7"));
  assert(html.includes('src="https://app.gameall.in/logo-icon.png"'));
  assert(html.includes("One Time Password"));
  assert(!html.includes("Club Management") && !text.includes("Club Management"));
  assert(!html.includes("<b>"), "name must be escaped");
  assert(subject.includes("042917") && text.includes("042917"));
});
