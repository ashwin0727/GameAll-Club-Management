import { z } from "zod";

export const otherSportNameSchema = z
  .string()
  .trim()
  .min(2, "Sport name must be at least 2 characters")
  .max(50, "Keep this under 50 characters");