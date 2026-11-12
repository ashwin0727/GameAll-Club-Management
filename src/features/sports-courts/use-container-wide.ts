import * as React from "react";

/**
 * Whether an element is at least [min] px wide — measured on the element itself, not the window. A table that needs ~780px to lay
 * its columns out has to react to the space it really has (which shrinks with browser zoom, the sidebar and nested panels), so a
 * window breakpoint is the wrong test. Returns a callback ref to put on the element, and the answer (false until measured).
 */
export function useContainerWide(min: number): [(el: HTMLElement | null) => void, boolean] {
  const [el, setEl] = React.useState<HTMLElement | null>(null);
  const [wide, setWide] = React.useState(false);

  React.useEffect(() => {
    if (!el) return;
    const measure = (width: number) => setWide(width >= min);
    measure(el.clientWidth);
    const observer = new ResizeObserver((entries) => measure(entries[0]?.contentRect.width ?? el.clientWidth));
    observer.observe(el);
    return () => observer.disconnect();
  }, [el, min]);

  return [setEl, wide];
}
