import { describe, expect, it } from "vitest";
import { nextSessions, sessionDayLabel } from "@/features/coaching/upcoming-sessions";

describe("nextSessions", () => {
  const s = (id: string, startAt: string) => ({ id, startAt });

  it("keeps the next two in start order", () => {
    const out = nextSessions([s("c", "2026-10-11T12:00:00Z"), s("a", "2026-10-11T10:30:00Z"), s("b", "2026-10-11T11:30:00Z")]);
    expect(out.map((x) => x.id)).toEqual(["a", "b"]);
  });

  it("spans days when only one session is left today", () => {
    const out = nextSessions([s("tomorrow", "2026-10-12T10:30:00Z"), s("today", "2026-10-11T10:30:00Z")]);
    expect(out.map((x) => x.id)).toEqual(["today", "tomorrow"]);
  });

  it("returns fewer when there are fewer, and does not mutate its input", () => {
    const input = [s("b", "2026-10-12T00:00:00Z"), s("a", "2026-10-11T00:00:00Z")];
    expect(nextSessions(input)).toHaveLength(2);
    expect(nextSessions([s("only", "2026-10-11T00:00:00Z")])).toHaveLength(1);
    expect(input[0]!.id).toBe("b");
  });
});

describe("sessionDayLabel", () => {
  const now = new Date(2026, 9, 11, 11, 0);
  it("says Today and Tomorrow, else the weekday and date", () => {
    expect(sessionDayLabel(new Date(2026, 9, 11, 16, 0).toISOString(), now)).toBe("Today");
    expect(sessionDayLabel(new Date(2026, 9, 12, 16, 0).toISOString(), now)).toBe("Tomorrow");
    expect(sessionDayLabel(new Date(2026, 9, 14, 16, 0).toISOString(), now)).toMatch(/14/);
  });
});
