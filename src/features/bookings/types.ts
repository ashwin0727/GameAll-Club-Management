import { z } from "zod";

export const courtSchema = z.object({
  id: z.string().uuid(),
  facility_id: z.string().uuid(),
  sport_id: z.string().uuid(),
  name: z.string().min(1),
  surface: z.string().nullable(),
  hourly_rate_inr: z.number().int().nonnegative(),
  is_active: z.boolean(),
});
export type Court = z.infer<typeof courtSchema>;

export const bookingStatusSchema = z.enum(["pending", "confirmed", "cancelled", "completed"]);

export const bookingSchema = z.object({
  id: z.string().uuid(),
  facility_id: z.string().uuid(),
  court_id: z.string().uuid(),
  member_id: z.string().uuid(),
  start_time: z.string(),
  end_time: z.string(),
  status: bookingStatusSchema,
  created_by: z.string().uuid(),
  created_at: z.string(),
});
export type Booking = z.infer<typeof bookingSchema>;

// Next slice: api/, hooks/, and calendar components for this feature. Overlapping
// bookings are rejected by the database (bookings_no_overlap), so the UI only
// needs to surface that error, not police it.