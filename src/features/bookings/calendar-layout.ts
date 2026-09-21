import type { CalEvent } from "@/features/bookings/calendar-events";
import { startOfDay } from "@/features/bookings/calendar-events";
import type { MinuteWindow } from "@/features/bookings/slots";

export interface PositionedEvent {
  event: CalEvent;
  /** px from the top of the grid body. */
  top: number;
  /** px tall — never below the minimum, so short bookings stay readable. */
  height: number;
  /** Which side-by-side column this block occupies among overlapping blocks. */
  lane: number;
  /** How many side-by-side columns its overlap cluster needs (>= 1). */
  lanes: number;
}

export interface LayoutOptions {
  /** Grid window, minutes from midnight. */
  startMin: number;
  endMin: number;
  pxPerMin: number;
  /** Shortest height a block is drawn at. */
  minHeightPx: number;
  /**
   * Most side-by-side blocks drawn in one overlap cluster. Anything beyond that
   * is not drawn but counted, so a busy day summarises as "+N more" instead of
   * squeezing every booking into a sliver. Unset = draw everything.
   */
  maxLanes?: number;
  /** Rank of a court (0 = first). Within a cluster, lower ranks take the earlier lanes. */
  courtOrder?: (courtId: string) => number;
}

/** A cluster whose extra blocks were left out — drawn as a "+N more" pill. */
export interface OverflowMarker {
  key: string;
  /** px from the top of the grid body: where the cluster starts and ends. */
  top: number;
  bottom: number;
  count: number;
}

interface Item {
  event: CalEvent;
  s: number;
  e: number;
  /** End used for overlap — stretched to the minimum height so a stubby block never draws over its neighbour. */
  eff: number;
  lane: number;
  lanes: number;
  hidden: boolean;
}

/**
 * Turns one day's events for one column into absolutely-positioned blocks.
 * Events that overlap (in the space they will actually occupy) are split into
 * side-by-side lanes instead of drawing on top of each other, which is what
 * keeps a booked slot aligned with its row. Within an overlap cluster, courts
 * take lanes in court order — Court 1 first, then Court 2 — and blocks past
 * `maxLanes` are reported as overflow rather than drawn.
 */
export function layoutWithOverflow(
  events: CalEvent[],
  day: Date,
  opts: LayoutOptions,
): { blocks: PositionedEvent[]; overflow: OverflowMarker[] } {
  const dayStart = startOfDay(day).getTime();
  const minMinutes = opts.minHeightPx / opts.pxPerMin;
  const cap = opts.maxLanes ?? Infinity;
  const rank = (e: CalEvent) => opts.courtOrder?.(e.courtId) ?? 0;

  const items: Item[] = [];
  for (const event of events) {
    const s = Math.max((event.start.getTime() - dayStart) / 60000, opts.startMin);
    const e = Math.min((event.end.getTime() - dayStart) / 60000, opts.endMin);
    if (e <= s) continue;
    items.push({ event, s, e, eff: Math.max(e, s + minMinutes), lane: 0, lanes: 1, hidden: false });
  }
  items.sort((a, b) => a.s - b.s || b.e - a.e);

  // Pass 1: group into clusters of transitively-overlapping blocks.
  const clusters: Item[][] = [];
  let current: Item[] = [];
  let clusterEnd = -Infinity;
  for (const it of items) {
    if (it.s >= clusterEnd && current.length > 0) {
      clusters.push(current);
      current = [];
    }
    current.push(it);
    clusterEnd = current.length === 1 ? it.eff : Math.max(clusterEnd, it.eff);
  }
  if (current.length > 0) clusters.push(current);

  // Pass 2: inside each cluster, hand out lanes in court order.
  const overflow: OverflowMarker[] = [];
  clusters.forEach((cluster, index) => {
    const ordered = [...cluster].sort((a, b) => rank(a.event) - rank(b.event) || a.s - b.s || b.e - a.e);
    const laneEnds: number[] = [];
    for (const it of ordered) {
      let lane = laneEnds.findIndex((end) => end <= it.s);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.push(it.eff);
      } else {
        laneEnds[lane] = it.eff;
      }
      it.lane = lane;
    }
    const lanes = Math.min(Math.max(laneEnds.length, 1), cap);
    let hiddenCount = 0;
    for (const it of cluster) {
      it.lanes = lanes;
      if (it.lane >= cap) {
        it.hidden = true;
        hiddenCount++;
      }
    }
    if (hiddenCount > 0) {
      overflow.push({
        key: `${index}-${cluster[0]!.event.id}`,
        top: (Math.min(...cluster.map((i) => i.s)) - opts.startMin) * opts.pxPerMin,
        bottom: (Math.max(...cluster.map((i) => i.e)) - opts.startMin) * opts.pxPerMin,
        count: hiddenCount,
      });
    }
  });

  const blocks = items
    .filter((it) => !it.hidden)
    .map((it) => ({
      event: it.event,
      top: (it.s - opts.startMin) * opts.pxPerMin,
      height: Math.max((it.e - it.s) * opts.pxPerMin, opts.minHeightPx),
      lane: it.lane,
      lanes: it.lanes,
    }));
  return { blocks, overflow };
}

export function layoutEvents(events: CalEvent[], day: Date, opts: LayoutOptions): PositionedEvent[] {
  return layoutWithOverflow(events, day, opts).blocks;
}

/**
 * The hour range the grid spans: everything any court is open, widened to fit
 * any event that falls outside it, so a booked slot is never cropped away.
 */
export function computeGridHours(
  openWindows: MinuteWindow[],
  events: CalEvent[],
  days: Date[],
  fallback = { startHour: 6, endHour: 22 },
): { startHour: number; endHour: number } {
  const starts: number[] = openWindows.map((w) => w.startMin);
  const ends: number[] = openWindows.map((w) => w.endMin);

  for (const day of days) {
    const dayStart = startOfDay(day).getTime();
    for (const e of events) {
      const s = (e.start.getTime() - dayStart) / 60000;
      const en = (e.end.getTime() - dayStart) / 60000;
      if (en <= 0 || s >= 1440) continue;
      starts.push(Math.max(s, 0));
      ends.push(Math.min(en, 1440));
    }
  }

  if (starts.length === 0) return fallback;

  let startHour = Math.floor(Math.min(...starts) / 60);
  let endHour = Math.ceil(Math.max(...ends) / 60);
  startHour = Math.max(0, startHour);
  endHour = Math.min(24, endHour);
  if (endHour - startHour < 4) endHour = Math.min(24, startHour + 4);
  if (endHour - startHour < 4) startHour = Math.max(0, endHour - 4);
  return { startHour, endHour };
}

/** The parts of [startMin, endMin) that fall outside every open window — drawn shaded as "closed". */
export function closedSpans(open: MinuteWindow[], startMin: number, endMin: number): MinuteWindow[] {
  const sorted = [...open].sort((a, b) => a.startMin - b.startMin);
  const out: MinuteWindow[] = [];
  let cursor = startMin;
  for (const w of sorted) {
    if (w.startMin > cursor) out.push({ startMin: cursor, endMin: Math.min(w.startMin, endMin) });
    cursor = Math.max(cursor, w.endMin);
    if (cursor >= endMin) break;
  }
  if (cursor < endMin) out.push({ startMin: cursor, endMin });
  return out.filter((s) => s.endMin > s.startMin);
}
