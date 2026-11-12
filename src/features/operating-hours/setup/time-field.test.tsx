import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { TimeField } from "@/features/operating-hours/setup/hours-parts";
import { TIME_OPTIONS } from "@/features/operating-hours/setup-model";

describe("TimeField", () => {
  it("lists every half hour of the day as 12-hour times, midnight first", async () => {
    const user = userEvent.setup();
    render(<TimeField id="t" ariaLabel="Opens at" value="06:00" onChange={() => {}} />);

    expect(TIME_OPTIONS).toHaveLength(48);
    expect(TIME_OPTIONS[0]).toEqual({ value: "00:00", label: "12:00 AM" });
    expect(TIME_OPTIONS[47]).toEqual({ value: "23:30", label: "11:30 PM" });

    await user.click(screen.getByRole("combobox", { name: "Opens at" }));
    expect(await screen.findAllByRole("option")).toHaveLength(48);
    expect(screen.getByRole("option", { name: "6:00 AM" })).toBeInTheDocument();
  });

  it("picks a time and reports its 24-hour value", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<TimeField id="t" ariaLabel="Closes at" value="23:00" onChange={onChange} />);

    await user.click(screen.getByRole("combobox", { name: "Closes at" }));
    await user.click(await screen.findByRole("option", { name: "10:30 PM" }));
    expect(onChange).toHaveBeenCalledWith("22:30");
  });

  it("keeps a saved time that is not on the half hour as an extra choice", async () => {
    const user = userEvent.setup();
    render(<TimeField id="t" ariaLabel="Opens at" value="06:15" onChange={() => {}} />);

    expect(screen.getByRole("combobox", { name: "Opens at" })).toHaveTextContent("6:15 AM");
    await user.click(screen.getByRole("combobox", { name: "Opens at" }));
    expect(await screen.findAllByRole("option")).toHaveLength(49);
  });

  it("can be disabled (a closed day)", () => {
    render(<TimeField id="t" ariaLabel="Opens at" value="" onChange={() => {}} disabled placeholder="–" />);
    expect(screen.getByRole("combobox", { name: "Opens at" })).toBeDisabled();
  });
});
