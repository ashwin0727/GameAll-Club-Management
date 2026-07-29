import { z } from "zod";

export const stationSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  type: z.string().min(1),
  hourly_rate_inr: z.number().int().nonnegative(),
  is_active: z.boolean(),
});
export type Station = z.infer<typeof stationSchema>;

export const bookingStatusSchema = z.enum(["pending", "confirmed", "cancelled", "completed"]);

export const bookingSchema = z.object({
  id: z.string().uuid(),
  member_id: z.string().uuid(),
  station_id: z.string().uuid(),
  start_time: z.string(),
  end_time: z.string(),
  status: bookingStatusSchema,
  created_by: z.string().uuid(),
  created_at: z.string(),
});
export type Booking = z.infer<typeof bookingSchema>;

// Next slice: api/, hooks/, and FullCalendar-based components for this feature.