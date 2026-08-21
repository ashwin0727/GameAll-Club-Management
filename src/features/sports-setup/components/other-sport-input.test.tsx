import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { OtherSportInput } from "@/features/sports-setup/components/other-sport-input";

describe("OtherSportInput", () => {
  it("renders the Sport Name label and current value", () => {
    render(<OtherSportInput value="Basketball" onChange={vi.fn()} />);
    expect(screen.getByLabelText("Sport Name")).toHaveValue("Basketball");
  });

  it("calls onChange as the user types", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<OtherSportInput value="" onChange={onChange} />);

    await user.type(screen.getByLabelText("Sport Name"), "B");

    expect(onChange).toHaveBeenCalledWith("B");
  });

  it("shows an error message when provided", () => {
    render(<OtherSportInput value="" onChange={vi.fn()} error="Sport name must be at least 2 characters" />);
    expect(screen.getByText("Sport name must be at least 2 characters")).toBeInTheDocument();
  });
});