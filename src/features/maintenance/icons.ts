import {
  Cog,
  Droplet,
  Grid3x3,
  Lightbulb,
  Lock,
  MoreHorizontal,
  PaintBucket,
  Snowflake,
  Wrench,
  type LucideIcon,
} from "lucide-react";
import type { MaintenanceIconKey } from "@/features/maintenance/types";

/**
 * The one place a category icon key maps to a lucide component — the
 * "existing icon registry" the Issue Category picker (spec §10) reads from,
 * never a manually-drawn SVG.
 */
export const MAINTENANCE_ICON_MAP: Record<MaintenanceIconKey, LucideIcon> = {
  court: Grid3x3,
  lightbulb: Lightbulb,
  grid: Grid3x3,
  snowflake: Snowflake,
  cog: Cog,
  droplet: Droplet,
  lock: Lock,
  paint: PaintBucket,
  wrench: Wrench,
  more: MoreHorizontal,
};

export function maintenanceIcon(key: string): LucideIcon {
  return MAINTENANCE_ICON_MAP[key as MaintenanceIconKey] ?? Wrench;
}
