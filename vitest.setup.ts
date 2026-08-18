import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";
import { resetRouterMock } from "@/test/router-mock";

// Applied to every suite: the auth screens all read the router and query string.
vi.mock("next/navigation", async () => {
  const { routerMock, getSearchParams } = await import("@/test/router-mock");
  return {
    useRouter: () => routerMock,
    useSearchParams: () => getSearchParams(),
    usePathname: () => "/",
    redirect: vi.fn(),
    notFound: vi.fn(),
  };
});

afterEach(() => {
  cleanup();
  resetRouterMock();
});