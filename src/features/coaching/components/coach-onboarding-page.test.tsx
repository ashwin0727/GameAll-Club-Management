import { beforeEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CoachOnboardingPage } from "@/features/coaching/components/coach-onboarding-page";
import { renderWithProviders } from "@/test/harness";
import { resetRouterMock, routerMock, setSearchParams } from "@/test/router-mock";
import type { CoachOnboarding } from "@/features/coaching/types";

const listCoachCandidates = vi.fn();
const startCoachOnboarding = vi.fn();
const saveCoachOnboardingStep = vi.fn();
const getCoachOnboarding = vi.fn();
const completeCoachOnboarding = vi.fn();
const listRoles = vi.fn();
const createStaff = vi.fn();
const uploadAvatar = vi.fn();

vi.mock("@/features/auth/context/permission-provider", () => ({
  usePermissionContext: () => ({ facilityId: "f1", facilityName: "Test Club", baseRole: "owner", can: () => true, canAny: () => true }),
}));
vi.mock("@/services/coaching", () => ({
  getCoachingService: () => ({ listCoachCandidates, startCoachOnboarding, saveCoachOnboardingStep, getCoachOnboarding, completeCoachOnboarding }),
}));
vi.mock("@/services/staff", () => ({ getStaffService: () => ({ listRoles, createStaff, uploadAvatar }) }));
vi.mock("@/features/facility/hooks/use-facility-sport-options", () => ({
  useFacilitySportOptions: () => ({ data: [{ facilitySportId: "fs-badminton", name: "Badminton", icon: "🏸" }] }),
}));

const CANDIDATE = { userId: "u1", fullName: "Priya Sharma", email: "priya@x.com", phone: "9876543210", avatarUrl: null, title: "Front Desk" };

const SAVED: CoachOnboarding = {
  coachId: "c1",
  userId: "u1",
  currentStep: 3,
  stepsDone: [1, 2],
  onboardingStatus: "DRAFT",
  payoutStatus: "PENDING",
  canManagePayouts: true,
  data: {
    displayName: "Priya Sharma", location: "Chennai", timezone: "Asia/Kolkata", languages: ["English"], shortBio: "", dateOfBirth: null,
    niche: "Badminton", subSpecialties: [], experienceYears: 4, targetAudience: [], methodology: "", certificates: [],
    sportIds: ["fs-badminton"], expertiseLevels: ["Beginner"], sessionFormats: [], sessionDurations: [], defaultSessionDurationMinutes: null,
    perSessionRateMinor: null, weeklyRateMinor: null, monthlyRateMinor: null, availability: [],
  },
  payout: null,
};

describe("CoachOnboardingPage", () => {
  beforeEach(() => {
    resetRouterMock();
    setSearchParams("");
    listCoachCandidates.mockReset().mockResolvedValue([CANDIDATE]);
    listRoles.mockReset().mockResolvedValue([]);
    startCoachOnboarding.mockReset().mockResolvedValue("c1");
    saveCoachOnboardingStep.mockReset().mockResolvedValue(undefined);
    getCoachOnboarding.mockReset().mockResolvedValue(SAVED);
    completeCoachOnboarding.mockReset().mockResolvedValue(undefined);
  });

  it("starts on step 1 of 5 and Save & continue disabled until valid", async () => {
    renderWithProviders(<CoachOnboardingPage />);
    expect(await screen.findByText(/Step 1 of 5 · Identity & Basic Profile/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Save & continue/ })).toBeDisabled();
  });

  it("a new person's Display Name is their whole first name as it is typed, until the owner edits it", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachOnboardingPage />);
    await user.click(await screen.findByRole("button", { name: /new person/i }));
    await user.type(await screen.findByLabelText(/First Name/), "Sathish");
    expect(screen.getByLabelText(/Display Name/)).toHaveValue("Sathish");
    await user.type(screen.getByLabelText(/Last Name/), "Kumar");
    expect(screen.getByLabelText(/Display Name/)).toHaveValue("Sathish");
    await user.type(screen.getByLabelText(/Display Name/), " K");
    await user.type(screen.getByLabelText(/First Name/), "x");
    expect(screen.getByLabelText(/Display Name/)).toHaveValue("Sathish K");
  });

  it("after the coach is submitted, 'Go to Coaches List' goes to the Coaching page", async () => {
    const user = userEvent.setup();
    setSearchParams("coach=c1&step=5");
    getCoachOnboarding.mockResolvedValue({ ...SAVED, currentStep: 5, stepsDone: [1, 2, 3, 4] });
    renderWithProviders(<CoachOnboardingPage />);
    for (const name of [/Terms of service/, /code of ethics/, /Privacy/, /Platform commission/]) {
      await user.click(await screen.findByRole("checkbox", { name }));
    }
    await user.click(screen.getByRole("button", { name: /Submit & Activate Coach/ }));
    await user.click(await screen.findByRole("button", { name: /Go to Coaches List/ }));
    expect(routerMock.push).toHaveBeenCalledWith("/coaching");
  });

  it("picking a staff member and continuing creates the draft once and moves to step 2", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachOnboardingPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await user.click(await screen.findByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/));
    const next = screen.getByRole("button", { name: /Save & continue/ });
    await waitFor(() => expect(next).toBeEnabled());
    await user.dblClick(next); // a double tap must not create two drafts
    expect(await screen.findByText(/Step 2 of 5 · Expertise & Credentials/)).toBeInTheDocument();
    expect(startCoachOnboarding).toHaveBeenCalledTimes(1);
    expect(startCoachOnboarding.mock.calls[0]?.[1]).toBe("u1");
  });

  it("the address bar gaining ?coach= after step 1 saves does NOT reload the draft over what is on screen", async () => {
    const user = userEvent.setup();
    renderWithProviders(<CoachOnboardingPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await user.click(await screen.findByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/));
    await user.click(screen.getByRole("button", { name: /Save & continue/ }));
    expect(await screen.findByText(/Step 2 of 5 · Expertise & Credentials/)).toBeInTheDocument();

    // Next.js reflects the page's history.replaceState into useSearchParams — emulate that, then keep typing.
    setSearchParams("coach=c1&step=2");
    await user.type(screen.getByLabelText(/Coaching Niche/), "Tennis");

    expect(getCoachOnboarding).not.toHaveBeenCalled();
    expect(screen.getByText(/Step 2 of 5 · Expertise & Credentials/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Coaching Niche/)).toHaveValue("Tennis");

    // …and going back to step 1 still shows what was entered there.
    await user.click(screen.getByRole("button", { name: /Back/ }));
    expect(await screen.findByDisplayValue("Priya Sharma")).toBeInTheDocument();
  });

  it("?coach= resumes a draft on its saved step with the saved values (not a blank form)", async () => {
    setSearchParams("coach=c1");
    renderWithProviders(<CoachOnboardingPage />);
    expect(await screen.findByText(/Step 3 of 5 · Sessions & Pricing/)).toBeInTheDocument();
    expect(getCoachOnboarding).toHaveBeenCalledWith("c1");
    await userEvent.setup().click(screen.getByRole("button", { name: /Back/ }));
    expect(await screen.findByDisplayValue("Badminton")).toBeInTheDocument(); // step 2's saved niche
  });

  it("?step= overrides the landing step of a resumed draft", async () => {
    setSearchParams("coach=c1&step=4");
    renderWithProviders(<CoachOnboardingPage />);
    expect(await screen.findByText(/Step 4 of 5 · Payments, Payouts & KYC/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Finish later" })).toBeInTheDocument();
  });
});
