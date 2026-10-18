/**
 * Which of the facility's sports the app is showing. `null` is "All Sports" — the default, and what a
 * stale or empty choice falls back to. Otherwise it is the explicit subset the user ticked in the top bar.
 */
export type SportSelection = string[] | null;

export interface ResolvedSportSelection {
  /** The sports in view, in the facility's own order. Always at least one once the sport list has loaded. */
  ids: string[];
  /** Every sport is in view — nothing needs filtering. */
  isAll: boolean;
}

/**
 * The stored choice checked against the sports the facility actually has: ids that no longer exist (another
 * facility, a removed sport) drop out, and an empty result means All Sports rather than nothing.
 */
export function resolveSportSelection(stored: SportSelection, optionIds: string[]): ResolvedSportSelection {
  if (stored === null) return { ids: optionIds, isAll: true };
  const valid = optionIds.filter((id) => stored.includes(id));
  if (valid.length === 0 || valid.length === optionIds.length) return { ids: optionIds, isAll: true };
  return { ids: valid, isAll: false };
}

/**
 * Ticks or unticks one sport. The last sport left can't be unticked (there is always something to show), and
 * ticking every sport is the same as "All Sports", stored as `null`.
 */
export function toggleSportSelection(stored: SportSelection, optionIds: string[], id: string): SportSelection {
  const current = resolveSportSelection(stored, optionIds).ids;
  if (current.includes(id)) {
    if (current.length === 1) return stored;
    const next = current.filter((x) => x !== id);
    return next.length === optionIds.length ? null : next;
  }
  const next = optionIds.filter((x) => x === id || current.includes(x));
  return next.length === optionIds.length ? null : next;
}

/** "All Sports", "Badminton", "Badminton, Cricket" — the top bar's label. */
export function sportSelectionLabel(selection: ResolvedSportSelection, names: ReadonlyMap<string, string>): string {
  if (selection.isAll) return "All Sports";
  const picked = selection.ids.map((id) => names.get(id)).filter((n): n is string => Boolean(n));
  if (picked.length <= 2) return picked.join(", ");
  return `${picked[0]} +${picked.length - 1}`;
}
