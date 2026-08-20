import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LeaveConfirmDialog } from "@/features/onboarding/components/leave-confirm-dialog";

describe("LeaveConfirmDialog", () => {
  it("shows the saved-progress message when open", () => {
    render(<LeaveConfirmDialog open onOpenChange={vi.fn()} onLeave={vi.fn()} />);
    expect(screen.getByText("Your progress has been saved.")).toBeInTheDocument();
  });

  it("calls onLeave when Leave is clicked", async () => {
    const user = userEvent.setup();
    const onLeave = vi.fn();
    render(<LeaveConfirmDialog open onOpenChange={vi.fn()} onLeave={onLeave} />);

    await user.click(screen.getByRole("button", { name: "Leave" }));
    expect(onLeave).toHaveBeenCalled();
  });

  it("closes without leaving when Continue Setup is clicked", async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    const onLeave = vi.fn();
    render(<LeaveConfirmDialog open onOpenChange={onOpenChange} onLeave={onLeave} />);

    await user.click(screen.getByRole("button", { name: "Continue Setup" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(onLeave).not.toHaveBeenCalled();
  });
});
