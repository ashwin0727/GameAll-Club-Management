"use client";

import { useEffect, useMemo, useState } from "react";
import {
  CalendarDays,
  ClipboardList,
  ExternalLink,
  GitFork,
  ListChecks,
  Rocket,
  ShieldCheck,
  Trophy,
  Users,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { resolveTournamentAppLinks, tournamentAppConfig } from "@/config/tournament-app";
import { trackTournamentEvent } from "@/features/tournaments/analytics";
import { TournamentAppPreview } from "./tournament-app-preview";

const FEATURES = [
  {
    icon: Trophy,
    title: "Create & Manage Tournaments",
    body: "Set up single elimination, round robin or league formats with categories, seeding and venue rules.",
  },
  {
    icon: Users,
    title: "Player & Team Registrations",
    body: "Open registration links, collect entries and payments, and manage waitlists without spreadsheets.",
  },
  {
    icon: CalendarDays,
    title: "Fixtures & Scheduling",
    body: "Auto-generate draws and match schedules across courts and days, then adjust with a drag.",
  },
  {
    icon: ListChecks,
    title: "Live Scores & Results",
    body: "Update match scores in real time and publish standings and brackets your players can follow.",
  },
  {
    icon: ClipboardList,
    title: "Tournament Operations",
    body: "Coordinate officials, notifications and on-site check-in from one organizer dashboard.",
  },
] as const;

const WHY_SEPARATE = [
  {
    icon: Rocket,
    title: "Built for Match Day",
    body: "A focused organizer tool with draws, live scoring and brackets — designed for the pace of a live event.",
  },
  {
    icon: ShieldCheck,
    title: "Your Facility Stays Clean",
    body: "Bookings, memberships and finance keep working exactly as they do today, with no tournament clutter.",
  },
  {
    icon: GitFork,
    title: "Independent Updates",
    body: "The tournament team ships new formats and features on its own schedule without disrupting operations here.",
  },
] as const;

const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.gameall.gameall&hl=en_IN";

/** The Google Play triangle, in its four brand colours. */
function PlayStoreIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true">
      <path fill="#00D7FE" d="M3.6 1.8c-.3.3-.5.8-.5 1.4v17.6c0 .6.2 1.1.5 1.4l9.9-10.2z" />
      <path fill="#00F076" d="M17 8.4 13.5 12l3.5 3.6 4-2.3c1.1-.6 1.1-1.6 0-2.2z" transform="translate(0 0)" />
      <path fill="#FF3A44" d="M3.6 22.2c.4.4 1 .4 1.7.1L17 15.6 13.5 12z" />
      <path fill="#FFD500" d="M3.6 1.8 13.5 12 17 8.4 5.3 1.7c-.7-.4-1.3-.3-1.7.1z" />
    </svg>
  );
}

function PlayStoreBadge({ onClick }: { onClick: () => void }) {
  return (
    <a
      href={PLAY_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      onClick={onClick}
      aria-label="Get GameAll on Google Play"
      className="inline-flex h-12 items-center gap-3 rounded-lg bg-[#171717] px-4 text-white transition-colors hover:bg-black focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
      <PlayStoreIcon className="h-6 w-6 shrink-0" />
      <span className="flex flex-col text-left leading-tight">
        <span className="text-[10px] font-medium uppercase tracking-wide">Get it on</span>
        <span className="text-base font-semibold">Google Play</span>
      </span>
    </a>
  );
}

type LaunchState = "idle" | "failed";

export function TournamentManagementPage() {
  const links = useMemo(() => resolveTournamentAppLinks(), []);
  const [launch, setLaunch] = useState<LaunchState>("idle");

  useEffect(() => {
    trackTournamentEvent("tournament_management_opened");
  }, []);

  const openApp = () => {
    if (!links.openUrl) return;
    trackTournamentEvent("tournament_app_open_clicked", { url: links.openUrl });
    const win = window.open(links.openUrl, "_blank", "noopener,noreferrer");
    // Popup blocked or the deep link had no handler — offer the stores instead.
    if (!win) {
      setLaunch("failed");
      trackTournamentEvent("tournament_app_launch_failed", { url: links.openUrl });
    }
  };

  const downloadHref = links.androidStoreUrl ?? links.iosStoreUrl ?? null;
  const onDownloadClick = () => trackTournamentEvent("tournament_app_download_clicked");

  const primaryCta = links.openUrl ? (
    <Button size="lg" onClick={openApp} className="w-full sm:w-auto">
      <ExternalLink className="h-4 w-4" aria-hidden />
      Open Tournament App
    </Button>
  ) : downloadHref ? (
    <Button asChild size="lg" className="w-full sm:w-auto">
      <a href={downloadHref} target="_blank" rel="noopener noreferrer" onClick={onDownloadClick}>
        Download App
        <ExternalLink className="h-4 w-4" aria-hidden />
      </a>
    </Button>
  ) : null;

  const secondaryCta =
    links.openUrl && links.hasStores ? (
      <Button asChild size="lg" variant="outline" className="w-full sm:w-auto">
        <a href={downloadHref ?? "#"} target="_blank" rel="noopener noreferrer" onClick={onDownloadClick}>
          Download App
        </a>
      </Button>
    ) : null;

  return (
    <div className="max-w-5xl space-y-10 pb-8">
      {/* Hero */}
      <section className="grid items-start gap-10 md:grid-cols-2">
        <div className="order-2 space-y-5 md:order-1">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-primary">Powered by GameAll</p>
          <h1 className="text-3xl font-semibold leading-tight sm:text-4xl">
            Bigger Tournaments.
            <br />
            Better Experiences.
          </h1>
          <p className="max-w-prose text-base text-muted-foreground">
            Tournament Management is a dedicated GameAll application for organizers and players. Run draws,
            registrations, schedules and live results from a tool built for competition — your facility operations
            stay right here.
          </p>

          {launch === "failed" && (
            <Card className="border-destructive/40 bg-destructive/5 p-4">
              <p className="text-sm font-medium text-destructive">We couldn&apos;t open the Tournament App.</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Install it from the store, or try opening it again.
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {downloadHref && (
                  <Button asChild size="sm" variant="outline">
                    <a href={downloadHref} target="_blank" rel="noopener noreferrer" onClick={onDownloadClick}>
                      Download App
                    </a>
                  </Button>
                )}
                {links.openUrl && (
                  <Button size="sm" onClick={openApp}>
                    Try Again
                  </Button>
                )}
              </div>
            </Card>
          )}

          <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
            {primaryCta}
            {secondaryCta}
          </div>
          {links.availabilityLabel && (
            <p className="text-xs text-muted-foreground">{links.availabilityLabel}</p>
          )}

          {/* Already have the app: in the hero so it is visible without scrolling. Text left, store button right. */}
          <Card className="flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between sm:gap-5">
            <div className="min-w-0 flex-1">
              <h2 className="text-lg font-semibold">Already have the app?</h2>
              <p className="mt-1 text-sm text-muted-foreground">Jump straight into your organizer dashboard.</p>
            </div>
            <div className="flex shrink-0 flex-col gap-3 sm:flex-row sm:items-center">
              {links.openUrl && (
                <Button size="lg" onClick={openApp} className="w-full sm:w-auto">
                  <ExternalLink className="h-4 w-4" aria-hidden />
                  Open Tournament App
                </Button>
              )}
              <PlayStoreBadge onClick={onDownloadClick} />
            </div>
          </Card>
        </div>

        <div className="order-1 md:order-2">
          <TournamentAppPreview images={tournamentAppConfig.previewImages} />
        </div>
      </section>

      {/* Features */}
      <section className="space-y-6">
        <h2 className="text-2xl font-semibold">Everything You Need for Tournament Success</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f) => (
            <FeatureCard key={f.title} icon={f.icon} title={f.title} body={f.body} />
          ))}
        </div>
      </section>

      {/* Why a separate application */}
      <section className="space-y-6">
        <div className="space-y-2">
          <h2 className="text-2xl font-semibold">Why a separate application?</h2>
          <p className="max-w-prose text-sm text-muted-foreground">
            Running a tournament and running a facility are different jobs. Keeping them in focused apps means each one
            stays fast, simple and reliable.
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          {WHY_SEPARATE.map((w) => (
            <FeatureCard key={w.title} icon={w.icon} title={w.title} body={w.body} />
          ))}
        </div>
      </section>

    </div>
  );
}

function FeatureCard({
  icon: Icon,
  title,
  body,
}: {
  icon: typeof Trophy;
  title: string;
  body: string;
}) {
  return (
    <Card className={cn("h-full p-5")}>
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
        <Icon className="h-5 w-5" aria-hidden />
      </div>
      <h3 className="mt-3 text-sm font-semibold">{title}</h3>
      <p className="mt-1 text-sm text-muted-foreground">{body}</p>
    </Card>
  );
}
