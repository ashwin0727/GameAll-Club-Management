import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DropdownSelect } from "@/components/shared/dropdown-select";

describe("DropdownSelect", () => {
  it("shows the chosen option's label and lists every <option>, however they are nested", async () => {
    const user = userEvent.setup();
    render(
      <DropdownSelect aria-label="Plan" value="b" onChange={vi.fn()}>
        <option value="">Select a plan</option>
        {["a", "b"].map((v) => (
          <option key={v} value={v}>
            Plan {v.toUpperCase()} · 2 slots
          </option>
        ))}
        <>
          <option value="c">Plan C</option>
        </>
      </DropdownSelect>,
    );

    const field = screen.getByRole("combobox", { name: "Plan" });
    expect(field).toHaveTextContent("Plan B · 2 slots");
    await user.click(field);
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual(["Select a plan", "Plan A · 2 slots", "Plan B · 2 slots", "Plan C"]);
  });

  it("calls onChange with an event whose target.value is the picked value, like a native select", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(
      <DropdownSelect aria-label="Court" value="1" onChange={(e) => onChange(e.target.value)}>
        <option value="1">Court 1</option>
        <option value="2">Court 2</option>
      </DropdownSelect>,
    );
    await user.click(screen.getByRole("combobox", { name: "Court" }));
    await user.click(screen.getByRole("option", { name: "Court 2" }));
    expect(onChange).toHaveBeenCalledWith("2");
  });

  it("does not pick a disabled option", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(
      <DropdownSelect aria-label="Court" value="1" onChange={() => onChange()}>
        <option value="1">Court 1</option>
        <option value="2" disabled>
          Court 2 (closed)
        </option>
      </DropdownSelect>,
    );
    await user.click(screen.getByRole("combobox", { name: "Court" }));
    await user.click(screen.getByRole("option", { name: "Court 2 (closed)" }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it("is not openable when disabled, and shows the first option when no value is given", async () => {
    const user = userEvent.setup();
    render(
      <DropdownSelect aria-label="Billing" disabled>
        <option>Auto-renewal</option>
      </DropdownSelect>,
    );
    const field = screen.getByRole("combobox", { name: "Billing" });
    expect(field).toHaveTextContent("Auto-renewal");
    await user.click(field);
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
  });

  it("a click on the list inside a <label> does not reopen it", async () => {
    const user = userEvent.setup();
    render(
      <label>
        Sport
        <DropdownSelect aria-label="Sport" value="x" onChange={vi.fn()}>
          <option value="x">Badminton</option>
          <option value="y">Cricket</option>
        </DropdownSelect>
      </label>,
    );
    await user.click(screen.getByRole("combobox", { name: "Sport" }));
    await user.click(screen.getByRole("option", { name: "Cricket" }));
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
  });
});
