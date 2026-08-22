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

  it("opens the leave-confirm dialog when going Back with unsaved progress, and Leave navigates to the previous step", async () => {
    const user = userEvent.setup();
    setPathname("/onboarding/sports");
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton"]);

    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );

    await user.click(screen.getByRole("button", { name: "Back" }));

    expect(await screen.findByText("Your progress has been saved.")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Leave" }));

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/facility"));
  });

  it("navigates straight to /dashboard with no dialog when there is no unsaved progress", async () => {
    const user = userEvent.setup();
    setPathname("/onboarding/facility");

    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );

    await user.click(screen.getByRole("button", { name: "Back" }));

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/dashboard"));
    expect(screen.queryByText("Your progress has been saved.")).not.toBeInTheDocument();
  });

  it("opens the leave-confirm dialog when the draft is empty but selectedSportIds is not", async () => {
    const user = userEvent.setup();
    setPathname("/onboarding/facility");
    useOnboardingStore.getState().setSelectedSportIds(["sport_cricket"]);

    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );

    await user.click(screen.getByRole("button", { name: "Back" }));

    expect(await screen.findByText("Your progress has been saved.")).toBeInTheDocument();
    expect(routerMock.replace).not.toHaveBeenCalled();
  });

  it("navigates from /onboarding/courts back to /onboarding/sports when there is no unsaved progress", async () => {
    const user = userEvent.setup();
    setPathname("/onboarding/courts");

    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );

    await user.click(screen.getByRole("button", { name: "Back" }));

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
  });

  it("does not show the confirm dialog on /onboarding/courts even though earlier steps left draft/selectedSportIds populated", async () => {
    const user = userEvent.setup();
    setPathname("/onboarding/courts");
    // Facility and Sports steps never clear this state once completed —
    // Courts persists its own data incrementally, so neither field reflects
    // anything actually unsaved on this step.
    useOnboardingStore.getState().setDraft({ facilityName: "GameAll Sports Arena" });
    useOnboardingStore.getState().setSelectedSportIds(["sport_badminton"]);

    renderWithProviders(
      <OnboardingLayout>
        <div>content</div>
      </OnboardingLayout>,
    );

    await user.click(screen.getByRole("button", { name: "Back" }));

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith("/onboarding/sports"));
    expect(screen.queryByText("Your progress has been saved.")).not.toBeInTheDocument();
  });
});