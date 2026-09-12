/**
 * Tournament handoff analytics seam.
 *
 * GameAll Facility Management has no analytics platform wired up. Rather than
 * introduce one for this page, these calls are a thin seam: today they only
 * log in development, but every handoff interaction flows through one place so
 * a real sink can be attached later without touching the components.
 */
export type TournamentEvent =
  | "tournament_management_opened"
  | "tournament_app_open_clicked"
  | "tournament_app_download_clicked"
  | "tournament_app_launch_failed";

export function trackTournamentEvent(event: TournamentEvent, detail?: Record<string, unknown>): void {
  if (process.env.NODE_ENV !== "production") {
    // eslint-disable-next-line no-console
    console.debug(`[tournament] ${event}`, detail ?? {});
  }
}
