/** Exact path, or a real sub-path ("/memberships/new") — never a bare string prefix of a sibling route. */
function matches(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

/**
 * The ONE menu entry the current page belongs to: the most specific (longest) href that matches.
 * Several entries share a prefix — Coaching / Program / Students, Maintenance / Maintenance Tracker,
 * Members / Dashboard / Membership Schedule — so a plain prefix test would light up the parent
 * alongside the child. A page with no entry of its own (e.g. Court Schedule, which is no longer in
 * the menu) falls back to its nearest parent.
 */
export function activeHrefFor(pathname: string, hrefs: string[]): string | null {
  let best: string | null = null;
  for (const href of hrefs) {
    if (matches(pathname, href) && (best === null || href.length > best.length)) best = href;
  }
  return best;
}
