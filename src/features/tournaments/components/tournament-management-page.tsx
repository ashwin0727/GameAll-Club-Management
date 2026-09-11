"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
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
    title: "Built for match day",
    body: "A focused organizer tool with draws, live scoring and brackets — designed for the pace of a live event.",
  },
  {
    icon: ShieldCheck,
    title: "Your facility stays clean",
    body: "Bookings, memberships and finance keep working exactly as they do today, with no tournament clutter.",
  },
  {
    icon: GitFork,
    title: "Independent updates",
    body: "The tournament team ships new formats and features on its own schedule without disrupting operations here.",
  },
] as const;

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
      {/* Breadcrumb / back */}
      <div>
        <Link
          href="/dashboard"
          className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Dashboard
        </Link>
      </div>

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
          {!primaryCta && (
            <p className="text-sm text-muted-foreground">
              The Tournament App links aren&apos;t configured yet. Add them in your environment to enable this.
            </p>
          )}
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

      {/* Already have the app */}
      <section>
        <Card className="flex flex-col items-start gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-lg font-semibold">Already have the app?</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Jump straight into your organizer dashboard.
            </p>
          </div>
          {links.openUrl ? (
            <Button size="lg" onClick={openApp} className="w-full sm:w-auto">
              <ExternalLink className="h-4 w-4" aria-hidden />
              Open Tournament App
            </Button>
          ) : downloadHref ? (
            <Button asChild size="lg" className="w-full sm:w-auto">
              <a href={downloadHref} target="_blank" rel="noopener noreferrer" onClick={onDownloadClick}>
                Download App
              </a>
            </Button>
          ) : null}
        </Card>
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
