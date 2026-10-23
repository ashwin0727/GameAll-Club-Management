import { assertEquals } from "jsr:@std/assert@1";
import { buildDefaultPassword, buildStaffLogin, loginNamePart } from "./staff-login.ts";

// 2026-10-23 10:00:45 UTC = 15:30:45 in Asia/Kolkata (UTC+5:30)
const NOW = new Date("2026-10-23T10:00:45Z");

Deno.test("staff login is first name + DDMM + MMSS @gameall.co in the facility timezone", () => {
  assertEquals(buildStaffLogin("Ravi", NOW, "Asia/Kolkata"), "ravi23103045@gameall.co");
});

Deno.test("staff login cleans the name and falls back when nothing usable is left", () => {
  assertEquals(loginNamePart("Anne-Marie"), "annemarie");
  assertEquals(loginNamePart("  José "), "jose");
  assertEquals(loginNamePart("राम"), "staff");
});

Deno.test("a clash appends a counter", () => {
  assertEquals(buildStaffLogin("Ravi", NOW, "Asia/Kolkata", 2), "ravi231030452@gameall.co");
});

Deno.test("default password is Facility name @ HH:MM:SS", () => {
  assertEquals(buildDefaultPassword("Champz Turf", NOW, "Asia/Kolkata"), "Champz Turf@15:30:45");
});

Deno.test("midnight reads as 00, not 24", () => {
  assertEquals(buildDefaultPassword("X", new Date("2026-10-22T18:30:05Z"), "Asia/Kolkata"), "X@00:00:05");
});
