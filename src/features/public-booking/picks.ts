import { advanceMinor, needsAdvance } from "@/features/bookings/advance-payment";

/** One hour a player ticked on one court. */
export interface Pick {
  courtId: string;
  courtName: string;
  startTime: string;
  endTime: string;
  priceMinor: number;
}

/** One booking the player's picks turn into: a continuous stretch on one court. */
export interface BookingRequest {
  courtId: string;
  courtName: string;
  startTime: string;
  endTime: string;
  totalMinor: number;
  /** Longer than an hour → a 50% advance must be paid online before it is confirmed. */
  needsAdvance: boolean;
  advanceMinor: number;
}

export function samePick(a: Pick, b: Pick): boolean {
  return a.courtId === b.courtId && a.startTime === b.startTime;
}

/** Adds the pick, or removes it when it is already there. */
export function togglePick(picks: Pick[], pick: Pick): Pick[] {
  return picks.some((p) => samePick(p, pick)) ? picks.filter((p) => !samePick(p, pick)) : [...picks, pick];
}

const ms = (iso: string) => new Date(iso).getTime();

/**
 * The bookings to create: each court's picks in time order, with hours that touch joined into one booking
 * (6–7 + 7–8 on Court 1 is a single 6–8 booking; a gap, or another court, starts a new one). Courts keep the
 * order the player first picked them in.
 */
export function buildRequests(picks: Pick[]): BookingRequest[] {
  const courtOrder: string[] = [];
  for (const p of picks) if (!courtOrder.includes(p.courtId)) courtOrder.push(p.courtId);

  const out: BookingRequest[] = [];
  for (const courtId of courtOrder) {
    const mine = picks.filter((p) => p.courtId === courtId).sort((a, b) => ms(a.startTime) - ms(b.startTime));
    let current: BookingRequest | null = null;
    for (const p of mine) {
      if (current && ms(current.endTime) === ms(p.startTime)) {
        current.endTime = p.endTime;
        current.totalMinor += p.priceMinor;
      } else {
        if (current) out.push(current);
        current = { courtId, courtName: p.courtName, startTime: p.startTime, endTime: p.endTime, totalMinor: p.priceMinor, needsAdvance: false, advanceMinor: 0 };
      }
    }
    if (current) out.push(current);
  }
  for (const r of out) {
    r.needsAdvance = needsAdvance(r.startTime, r.endTime);
    r.advanceMinor = r.needsAdvance ? advanceMinor(r.totalMinor) : 0;
  }
  return out;
}

export interface PickSummary {
  requests: BookingRequest[];
  totalMinor: number;
  hours: number;
  /** Paid online now: the advance on every booking longer than an hour. */
  advanceDueMinor: number;
  /** Paid at the venue afterwards. */
  balanceMinor: number;
  advanceRequired: boolean;
}

export function summarise(picks: Pick[]): PickSummary {
  const requests = buildRequests(picks);
  const totalMinor = requests.reduce((s, r) => s + r.totalMinor, 0);
  const advanceDueMinor = requests.reduce((s, r) => s + r.advanceMinor, 0);
  const hours = picks.reduce((s, p) => s + (ms(p.endTime) - ms(p.startTime)) / 3_600_000, 0);
  return { requests, totalMinor, hours, advanceDueMinor, balanceMinor: totalMinor - advanceDueMinor, advanceRequired: advanceDueMinor > 0 };
}
