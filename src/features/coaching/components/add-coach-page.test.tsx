import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AddCoachPage } from "@/features/coaching/components/add-coach-page";
import { renderWithProviders } from "@/test/harness";
import { routerMock, resetRouterMock } from "@/test/router-mock";
import { ServiceError } from "@/services/shared/service-error";

const listCoachCandidates = vi.fn();
const addCoach = vi.fn();
const listRoles = vi.fn();
const createStaff = vi.fn();
const uploadAvatar = vi.fn();

vi.mock("@/features/auth/context/permission-provider", () => ({
  usePermissionContext: () => ({
    facilityId: "f1",
    facilityName: "Test Club",
    baseRole: "owner",
    permissions: new Set(["COACHING_MANAGE_COACHES"]),
    can: () => true,
    canAny: () => true,
  }),
}));

vi.mock("@/services/coaching", () => ({
  getCoachingService: () => ({ listCoachCandidates, addCoach }),
}));

vi.mock("@/services/staff", () => ({
  getStaffService: () => ({ listRoles, createStaff, uploadAvatar }),
}));

vi.mock("@/features/facility/hooks/use-facility-sport-options", () => ({
  useFacilitySportOptions: () => ({
    data: [
      { facilitySportId: "fs-badminton", name: "Badminton", icon: "🏸" },
      { facilitySportId: "fs-tennis", name: "Tennis", icon: "🎾" },
    ],
  }),
}));

const CANDIDATE = { userId: "u1", fullName: "Priya Sharma", email: "priya@x.com", phone: "9876543210", avatarUrl: null, title: "Front Desk" };
const ROLE = { id: "role-coach", key: null, name: "Coach", description: null, isSystem: false, isCustom: true, isActive: true, version: 1, staffCount: 0, permissionCount: 0 };

describe("AddCoachPage", () => {
  beforeEach(() => {
    listCoachCandidates.mockReset().mockResolvedValue([CANDIDATE]);
    addCoach.mockReset().mockResolvedValue("coach-1");
    listRoles.mockReset().mockResolvedValue([ROLE]);
    createStaff.mockReset();
    uploadAvatar.mockReset();
    resetRouterMock();
  });

  it("keeps Add Coach disabled until a staff member, a sport and an expertise level are chosen", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    const submit = screen.getByRole("button", { name: /\+ Add Coach/i });
    expect(submit).toBeDisabled();

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    expect(submit).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "Badminton" }));
    expect(submit).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "Beginner" }));
    expect(submit).not.toBeDisabled();
  });

  it("submits the picked candidate with sports, expertise and duration, then shows the success screen", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));
    await user.click(screen.getByRole("button", { name: /\+ Add Coach/i }));

    await waitFor(() =>
      expect(addCoach).toHaveBeenCalledWith(
        "f1",
        "u1",
        expect.objectContaining({
          sportIds: ["fs-badminton"],
          expertiseLevels: ["Beginner"],
          defaultSessionDurationMinutes: 60,
          status: "ACTIVE",
        }),
      ),
    );
    expect(createStaff).not.toHaveBeenCalled();
    expect(await screen.findByText("Coach Added Successfully!")).toBeInTheDocument();
    expect(screen.getByText(/Priya Sharma has been added/i)).toBeInTheDocument();
  });

  it("creates a new staff member first when '+ New person' is used, then adds the coach with that user's id", async () => {
    createStaff.mockResolvedValue({ userId: "new-user-1", linked: true, temporaryPassword: "temp123" });
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: "+ New person" }));
    await user.type(screen.getByLabelText(/Full Name/i), "Arjun V");
    await user.type(screen.getByLabelText(/^Email/i), "arjun@x.com");
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));

    await user.click(screen.getByRole("button", { name: /\+ Add Coach/i }));

    await waitFor(() =>
      expect(createStaff).toHaveBeenCalledWith(
        expect.objectContaining({ facilityId: "f1", fullName: "Arjun V", email: "arjun@x.com", roleId: "role-coach" }),
      ),
    );
    await waitFor(() => expect(addCoach).toHaveBeenCalledWith("f1", "new-user-1", expect.anything()));
    expect(await screen.findByText("Coach Added Successfully!")).toBeInTheDocument();
  });

  it("shows the service error and does not advance to the success screen when addCoach fails", async () => {
    addCoach.mockRejectedValue(new Error("boom"));
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));
    await user.click(screen.getByRole("button", { name: /\+ Add Coach/i }));

    expect(await screen.findByText("Could not add the coach.")).toBeInTheDocument();
    expect(screen.queryByText("Coach Added Successfully!")).not.toBeInTheDocument();
  });

  it("the success screen's next-action cards navigate to the right coach-scoped routes", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));
    await user.click(screen.getByRole("button", { name: /\+ Add Coach/i }));
    await screen.findByText("Coach Added Successfully!");

    await user.click(screen.getByText("Manage Availability"));
    expect(routerMock.push).toHaveBeenCalledWith("/coaching/coaches/coach-1?tab=Availability");
  });

  it("uploads the chosen photo for a new person and passes its URL to createStaff", async () => {
    createStaff.mockResolvedValue({ userId: "new-user-1", linked: true, temporaryPassword: "temp123" });
    uploadAvatar.mockResolvedValue("https://cdn.example/avatars/u1/photo.png");
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: "+ New person" }));
    await user.type(screen.getByLabelText(/Full Name/i), "Arjun V");
    await user.type(screen.getByLabelText(/^Email/i), "arjun@x.com");

    const file = new File(["fake-bytes"], "photo.png", { type: "image/png" });
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    await user.upload(fileInput, file);
    expect(screen.queryByText(/larger than 2MB|choose a JPG/i)).not.toBeInTheDocument(); // valid file, no error

    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));
    await user.click(screen.getByRole("button", { name: /\+ Add Coach/i }));

    await waitFor(() => expect(uploadAvatar).toHaveBeenCalledWith(file));
    await waitFor(() =>
      expect(createStaff).toHaveBeenCalledWith(
        expect.objectContaining({ avatarUrl: "https://cdn.example/avatars/u1/photo.png" }),
      ),
    );
  });

  it("rejects an oversized photo and does not call uploadAvatar", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await user.click(screen.getByRole("button", { name: "+ New person" }));

    const big = new File([new Uint8Array(3 * 1024 * 1024)], "big.png", { type: "image/png" });
    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    await user.upload(fileInput, big);

    expect(await screen.findByText(/larger than 2MB/i)).toBeInTheDocument();
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
  });

  it("reveals a minutes field for a Custom session duration and sends it to addCoach", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("combobox", { name: /staff member/i }));
    await user.click(await screen.findByText(/Priya Sharma/i));
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));

    await user.click(screen.getByRole("combobox", { name: /default session duration/i }));
    await user.click(await screen.findByRole("option", { name: "Custom" }));

    const submit = screen.getByRole("button", { name: /\+ Add Coach/i });
    expect(submit).toBeDisabled(); // custom minutes not filled in yet

    await user.type(screen.getByLabelText(/custom duration in minutes/i), "75");
    expect(submit).not.toBeDisabled();

    await user.click(submit);
    await waitFor(() =>
      expect(addCoach).toHaveBeenCalledWith("f1", "u1", expect.objectContaining({ defaultSessionDurationMinutes: 75 })),
    );
  });

  it("surfaces the real error (e.g. a permission denial) when the Role list fails to load, instead of a silently empty dropdown", async () => {
    listRoles.mockRejectedValue(new ServiceError("STAFF_ACCESS_DENIED", "You don't have permission to view roles."));
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: "+ New person" }));
    expect(await screen.findByText("You don't have permission to view roles.")).toBeInTheDocument();

    await user.click(screen.getByRole("combobox", { name: /role/i }));
    expect(await screen.findByText("Unable to load roles")).toBeInTheDocument();
  });

  async function fillMinimumNewPersonFields(user: ReturnType<typeof userEvent.setup>) {
    await user.click(screen.getByRole("button", { name: "+ New person" }));
    await user.type(screen.getByLabelText(/Full Name/i), "Arjun V");
    await user.click(screen.getByRole("button", { name: "Badminton" }));
    await user.click(screen.getByRole("button", { name: "Beginner" }));
  }

  it("blocks submit and shows an error for an incomplete phone number, but allows it once fixed or cleared", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await fillMinimumNewPersonFields(user);
    await user.type(screen.getByLabelText(/^Email/i), "arjun@x.com");

    const submit = screen.getByRole("button", { name: /\+ Add Coach/i });
    expect(submit).not.toBeDisabled(); // phone is optional and empty so far

    await user.type(screen.getByLabelText(/phone number/i), "98765");
    expect(await screen.findByText(/enter all 10 digits/i)).toBeInTheDocument();
    expect(submit).toBeDisabled();

    await user.type(screen.getByLabelText(/phone number/i), "43210");
    expect(screen.queryByText(/enter all 10 digits/i)).not.toBeInTheDocument();
    expect(submit).not.toBeDisabled();
  });

  it("strips non-digits and caps the phone field at 10 characters", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await user.click(screen.getByRole("button", { name: "+ New person" }));

    const phone = screen.getByLabelText(/phone number/i) as HTMLInputElement;
    await user.type(phone, "+91-98765-432109999");
    expect(phone.value).toBe("9198765432");
  });

  it("blocks submit for an invalid email address", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await fillMinimumNewPersonFields(user);

    await user.type(screen.getByLabelText(/^Email/i), "not-an-email");
    expect(await screen.findByText(/enter a valid email address/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /\+ Add Coach/i })).toBeDisabled();
  });

  it("blocks submit for a future or implausible date of birth", async () => {
    const user = userEvent.setup();
    renderWithProviders(<AddCoachPage />);
    await waitFor(() => expect(listCoachCandidates).toHaveBeenCalled());
    await fillMinimumNewPersonFields(user);
    await user.type(screen.getByLabelText(/^Email/i), "arjun@x.com");
    const submit = screen.getByRole("button", { name: /\+ Add Coach/i });
    expect(submit).not.toBeDisabled();

    const dob = screen.getByLabelText(/date of birth/i);
    fireEvent.change(dob, { target: { value: "2999-01-01" } });
    expect(await screen.findByText(/enter a valid date of birth/i)).toBeInTheDocument();
    expect(submit).toBeDisabled();

    fireEvent.change(dob, { target: { value: "1995-03-14" } });
    expect(screen.queryByText(/enter a valid date of birth/i)).not.toBeInTheDocument();
    expect(submit).not.toBeDisabled();
  });
});
