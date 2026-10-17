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

  it("goes straight from Sports back to Facility Details, with no confirmation, even with sports selected", async () => {
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton"]);
    await clickBack("/onboarding/sports");
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
    expect(screen.queryByText("Your progress has been saved.")).not.toBeInTheDocument();
  });

  it("goes straight to /dashboard from the first step, even with a draft", async () => {
    useOnboardingStore.getState().setDraft({ facilityName: "GameAll Sports Arena" });
    await clickBack("/onboarding/facility");
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/dashboard"));
    expect(screen.queryByText("Your progress has been saved.")).not.toBeInTheDocument();
  });

  it("goes from Courts back to Sports", async () => {
    await clickBack("/onboarding/courts");
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });
});
