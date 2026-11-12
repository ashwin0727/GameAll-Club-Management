import { beforeEach, describe, expect, it } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import OnboardingLayout from "@/app/onboarding/layout";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { renderWithProviders } from "@/test/harness";
import { routerMock, setPathname } from "@/test/router-mock";

describe("OnboardingLayout", () => {
  beforeEach(() => {
    window.localStorage.clear();
    useOnboardingStore.getState().reset();
  });

  async function clickBack(path: string) {
    const user = userEvent.setup();
    setPathname(path);
    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );
    await user.click(screen.getByRole("button", { name: "Back" }));
  }

  it("leaves the welcome, facility-information, sports & courts and operating-hours pages to their own shell (no header or Back button of its own)", () => {
    for (const path of ["/onboarding/welcome", "/onboarding/facility", "/onboarding/sports", "/onboarding/operating-hours", "/onboarding/pricing", "/onboarding/payments"]) {
      setPathname(path);
      const { unmount } = renderWithProviders(
        <OnboardingLayout>
          <div>content</div>
        </OnboardingLayout>,
      );
      expect(screen.getByText("content")).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "Back" })).not.toBeInTheDocument();
      unmount();
    }
  });

  it("goes from Courts back to Sports", async () => {
    await clickBack("/onboarding/courts");
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });

  it("goes from the plan step back to Payout", async () => {
    await clickBack("/onboarding/plan");
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/payments"));
  });
});
