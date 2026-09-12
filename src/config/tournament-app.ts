// ═══════════════════════════════════════════════════════════════════════════
// Tournament Management is a SEPARATE application. GameAll Facility Management
// only bridges to it — this is the one place the destination URLs live.
//
// Every URL comes from a NEXT_PUBLIC_TOURNAMENT_* environment variable (see
// .env.local.example). Nothing here is invented: when a URL is not
// configured, the corresponding call to action is hidden or disabled rather
// than pointing somewhere fake.
// ═══════════════════════════════════════════════════════════════════════════

export interface TournamentPreviewImage {
  /** A path under /public, or an absolute https URL. */
  src: string;
  /** What this screen of the app shows — used for the alt text and dot label. */
  label: string;
}

export interface TournamentAppConfig {
  /** The tournament app on the web. Opened by "Open Tournament App" on desktop. */
  webUrl: string | null;
  /** App / universal link. Tried first on mobile; a browser usually ignores it. */
  deepLink: string | null;
  /** Google Play listing. */
  androidStoreUrl: string | null;
  /** Apple App Store listing. */
  iosStoreUrl: string | null;
  /**
   * Actual screenshots of the Tournament Management app. One device is shown
   * at a time; the preview offers a quiet way to step between them. Drop the
   * real files at the paths below (or point the env var elsewhere) — the
   * page layout does not change.
   */
  previewImages: TournamentPreviewImage[];
}

function clean(value: string | undefined): string | null {
  const v = value?.trim();
  return v && v.length > 0 ? v : null;
}

export const tournamentAppConfig: TournamentAppConfig = {
  webUrl: clean(process.env.NEXT_PUBLIC_TOURNAMENT_WEB_URL),
  deepLink: clean(process.env.NEXT_PUBLIC_TOURNAMENT_DEEP_LINK),
  androidStoreUrl: clean(process.env.NEXT_PUBLIC_TOURNAMENT_ANDROID_URL),
  iosStoreUrl: clean(process.env.NEXT_PUBLIC_TOURNAMENT_IOS_URL),
  previewImages: buildPreviewImages(clean(process.env.NEXT_PUBLIC_TOURNAMENT_PREVIEW_IMAGE)),
};

function buildPreviewImages(override: string | null): TournamentPreviewImage[] {
  if (override) return [{ src: override, label: "App preview" }];
  return [
    { src: "/tournament-app-home.jpeg", label: "Organizer home" },
    { src: "/tournament-app-hub.jpeg", label: "Tournament hub" },
  ];
}

export interface TournamentAppLinks {
  /** Where "Open Tournament App" should point, or null when nothing is configured. */
  openUrl: string | null;
  /** True when at least one store link exists. */
  hasStores: boolean;
  androidStoreUrl: string | null;
  iosStoreUrl: string | null;
  /** Platform availability line — only shown when a real store link backs it. */
  availabilityLabel: string | null;
}

/**
 * Resolves the config into the links the UI actually renders. Pure — takes a
 * config so it is trivially testable.
 */
export function resolveTournamentAppLinks(config: TournamentAppConfig = tournamentAppConfig): TournamentAppLinks {
  const hasAndroid = Boolean(config.androidStoreUrl);
  const hasIos = Boolean(config.iosStoreUrl);
  const hasStores = hasAndroid || hasIos;

  const availabilityLabel = hasAndroid && hasIos
    ? "Available on Android and iOS"
    : hasAndroid
      ? "Available on Android"
      : hasIos
        ? "Available on iOS"
        : null;

  return {
    // Prefer the web app; fall back to the deep link; then the first store.
    openUrl: config.webUrl ?? config.deepLink ?? config.androidStoreUrl ?? config.iosStoreUrl,
    hasStores,
    androidStoreUrl: config.androidStoreUrl,
    iosStoreUrl: config.iosStoreUrl,
    availabilityLabel,
  };
}
