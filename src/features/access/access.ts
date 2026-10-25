import { ACCESS_PAGES, COACHING_OWN_ONLY, type AccessPage, type PageKey } from "./catalog.generated";

export { ACCESS_PAGES, COACHING_OWN_ONLY };
export type { AccessPage, PageKey };

/** None = the page does not exist for the person. View = read only. Edit = everything on the page (incl. export). */
export type AccessLevel = "none" | "view" | "edit";

/** custom = holds some, but not all, of the Edit keys (e.g. a role built before the matrix existed). */
export type EditorLevel = AccessLevel | "custom";

const BY_KEY = new Map<string, AccessPage>(ACCESS_PAGES.map((p) => [p.key, p]));

export function accessPage(key: string): AccessPage | undefined {
  return BY_KEY.get(key);
}

/** Every permission key the matrix manages. Keys outside this set (legacy / unmanaged) are preserved untouched on save. */
export const MANAGED_KEYS: ReadonlySet<string> = new Set([
  COACHING_OWN_ONLY,
  ...ACCESS_PAGES.flatMap((p) => [...p.viewKeys, ...p.editKeys, ...p.extraKeys]),
]);

/**
 * The level a person effectively has on a page, for gating the UI. Owners have everything. View needs every View key;
 * Edit means "can change something here" — any of the page's Edit keys, so a role with partial edit rights still gets
 * the buttons its own keys allow (each button is also gated by its specific key).
 */
export function levelFor(page: AccessPage, held: ReadonlySet<string>, isOwner: boolean): AccessLevel {
  if (isOwner) return "edit";
  if (!page.viewKeys.every((k) => held.has(k))) return "none";
  if (page.canEdit && page.editKeys.some((k) => held.has(k))) return "edit";
  return "view";
}

/** What the role editor shows: exact, so a half-edit role reads as "custom" instead of silently becoming Edit or View. */
export function editorLevelFor(page: AccessPage, held: ReadonlySet<string>): EditorLevel {
  if (!page.viewKeys.every((k) => held.has(k))) return "none";
  if (!page.canEdit || page.editKeys.length === 0) return "view";
  const have = page.editKeys.filter((k) => held.has(k)).length;
  if (have === 0) return "view";
  return have === page.editKeys.length ? "edit" : "custom";
}

export function levelsFromKeys(held: ReadonlySet<string>): Record<string, EditorLevel> {
  return Object.fromEntries(ACCESS_PAGES.map((p) => [p.key, editorLevelFor(p, held)]));
}

/**
 * The permission keys for a matrix: each page's View keys at View, plus its Edit keys at Edit, plus the chosen extras.
 * `custom` rows are left exactly as they were ([keep] supplies their current keys). Unmanaged keys in [keep] survive.
 */
export function expandAccess(
  levels: Record<string, EditorLevel>,
  extras: ReadonlySet<string>,
  ownOnly: boolean,
  keep: ReadonlySet<string> = new Set(),
): string[] {
  const out = new Set<string>();
  for (const k of keep) if (!MANAGED_KEYS.has(k)) out.add(k);
  for (const page of ACCESS_PAGES) {
    const level = levels[page.key] ?? "none";
    if (level === "none") continue;
    if (level === "custom") {
      for (const k of [...page.viewKeys, ...page.editKeys]) if (keep.has(k)) out.add(k);
    } else {
      page.viewKeys.forEach((k) => out.add(k));
      if (level === "edit") page.editKeys.forEach((k) => out.add(k));
    }
    // Extras only mean something when the page is reachable at all.
    for (const k of page.extraKeys) if (extras.has(k)) out.add(k);
  }
  if (ownOnly) out.add(COACHING_OWN_ONLY);
  return [...out];
}

export const ACCESS_GROUPS: { label: string; pages: AccessPage[] }[] = (() => {
  const groups: { label: string; pages: AccessPage[] }[] = [];
  for (const p of ACCESS_PAGES) {
    let g = groups.find((x) => x.label === p.group);
    if (!g) groups.push((g = { label: p.group, pages: [] }));
    g.pages.push(p);
  }
  return groups;
})();

/** Whether the person can open at least one page whose key starts with [prefix] (e.g. "COACHING_"). Owners always can. */
export function canViewAnyPage(held: readonly string[], isOwner: boolean, prefix: string[]): boolean {
  if (isOwner) return true;
  const set = new Set(held);
  return ACCESS_PAGES.some((p) => prefix.some((x) => p.key === x || p.key.startsWith(x)) && levelFor(p, set, false) !== "none");
}
