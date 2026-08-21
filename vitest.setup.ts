import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";
import { resetRouterMock } from "@/test/router-mock";

// Polyfills for Radix UI in jsdom
if (!Element.prototype.hasPointerCapture) {
  Element.prototype.hasPointerCapture = () => false;
}
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => {};
}

// Polyfills for URL APIs in jsdom
if (!URL.createObjectURL) {
  URL.createObjectURL = () => "blob:mock-url";
}
if (!URL.revokeObjectURL) {
  URL.revokeObjectURL = () => {};
}

// Applied to every suite: the auth screens all read the router and query string.
vi.mock("next/navigation", async () => {
  const { routerMock, getSearchParams, getPathname } = await import("@/test/router-mock");
  return {
    useRouter: () => routerMock,
    useSearchParams: () => getSearchParams(),
    usePathname: () => getPathname(),
    redirect: vi.fn(),
    notFound: vi.fn(),
  };
});

afterEach(() => {
  cleanup();
  resetRouterMock();
});