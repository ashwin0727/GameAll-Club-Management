import { vi } from "vitest";

/**
 * Stand-in for the App Router. The real one needs a Next server, so navigation
 * is asserted through these spies instead.
 */
export const routerMock = {
  push: vi.fn(),
  replace: vi.fn(),
  refresh: vi.fn(),
  prefetch: vi.fn(),
  back: vi.fn(),
  forward: vi.fn(),
};

let searchParams = new URLSearchParams();

export function setSearchParams(init: string | Record<string, string> = ""): void {
  searchParams = new URLSearchParams(init);
}

export function getSearchParams(): URLSearchParams {
  return searchParams;
}

export function resetRouterMock(): void {
  Object.values(routerMock).forEach((spy) => spy.mockReset());
  setSearchParams();
}