import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SubmitForReviewDialog } from "@/features/onboarding/components/submit-review-dialog";

describe("SubmitForReviewDialog", () => {
  it("shows the two statements and the next-steps note, and cannot be submitted until both are ticked", async () => {
    const onSubmit = vi.fn();
    render(<SubmitForReviewDialog open onSubmit={onSubmit} onCancel={() => undefined} />);
    const user = userEvent.setup();

    expect(screen.getByText("Confirm & Submit for Review")).toBeInTheDocument();
    expect(screen.getByText("What happens next?")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Terms and Conditions" })).toHaveAttribute("href", "/terms");
    expect(screen.getByRole("link", { name: "Privacy Policy" })).toHaveAttribute("href", "/privacy");

    const submit = screen.getByRole("button", { name: /Submit for Review/ });
    expect(submit).toBeDisabled();
    const [accurate, terms] = screen.getAllByRole("checkbox");
    await user.click(accurate!);
    expect(submit).toBeDisabled();
    await user.click(terms!);
    expect(submit).toBeEnabled();

    await user.click(submit);
    expect(onSubmit).toHaveBeenCalledTimes(1);
  });

  it("Cancel and the close button only dismiss it", async () => {
    const onSubmit = vi.fn();
    const onCancel = vi.fn();
    render(<SubmitForReviewDialog open onSubmit={onSubmit} onCancel={onCancel} />);
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Cancel" }));
    await user.click(screen.getAllByRole("button", { name: "Close" })[0]!);
    expect(onCancel).toHaveBeenCalledTimes(2);
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("while submitting it cannot be dismissed or sent twice", () => {
    render(<SubmitForReviewDialog open busy onSubmit={() => undefined} onCancel={() => undefined} />);
    expect(screen.getByRole("button", { name: "Cancel" })).toBeDisabled();
    expect(screen.getByRole("button", { name: /Submitting/ })).toBeDisabled();
  });
});
