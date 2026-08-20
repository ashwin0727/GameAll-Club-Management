"use client";

import { useDebouncedValue } from "@/hooks/use-debounced-value";

/**
 * `dirtyToken` is any value that changes on every draft edit (e.g. a
 * JSON.stringify of the draft, or an incrementing counter). While the
 * debounced copy hasn't caught up to the latest token, the save is "in
 * flight" from the user's point of view.
 */
export function SaveStatus({ dirtyToken, delayMs = 400 }: { dirtyToken: unknown; delayMs?: number }) {
  const settled = useDebouncedValue(dirtyToken, delayMs);
  const saving = settled !== dirtyToken;

  return (
    <p className="text-xs text-muted-foreground" role="status" aria-live="polite">
      {saving ? "Saving…" : "Saved"}
    </p>
  );
}
