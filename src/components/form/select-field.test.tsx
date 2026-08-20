import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SelectField } from "@/components/form/select-field";

const OPTIONS = [
  { value: "A", label: "Option A" },
  { value: "B", label: "Option B" },
];

describe("SelectField", () => {
  it("renders the label and current value", () => {
    render(
      <SelectField id="test" label="Test field" options={OPTIONS} value="A" onValueChange={vi.fn()} />,
    );

    expect(screen.getByText("Test field")).toBeInTheDocument();
    expect(screen.getByText("Option A")).toBeInTheDocument();
  });

  it("calls onValueChange when a new option is selected", async () => {
    const user = userEvent.setup();
    const onValueChange = vi.fn();
    render(
      <SelectField
        id="test"
        label="Test field"
        options={OPTIONS}
        value="A"
        onValueChange={onValueChange}
      />,
    );

    await user.click(screen.getByRole("combobox"));
    await user.click(await screen.findByRole("option", { name: "Option B" }));

    expect(onValueChange).toHaveBeenCalledWith("B");
  });

  it("shows an error message and marks the trigger invalid", () => {
    render(
      <SelectField
        id="test"
        label="Test field"
        options={OPTIONS}
        value="A"
        onValueChange={vi.fn()}
        error="This field is required"
      />,
    );

    expect(screen.getByText("This field is required")).toBeInTheDocument();
    expect(screen.getByRole("combobox")).toHaveAttribute("aria-invalid", "true");
  });
});
