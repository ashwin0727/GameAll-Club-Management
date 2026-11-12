import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SetupCalendar, SetupDatePicker } from "@/features/onboarding/components/setup-calendar";

describe("SetupCalendar", () => {
  it("opens on the chosen month, Monday first, and picks a date by click", async () => {
    const user = userEvent.setup();
    const onSelect = vi.fn();
    render(<SetupCalendar value="2026-12-25" onSelect={onSelect} />);

    expect(screen.getByText("December 2026")).toBeInTheDocument();
    expect(screen.getByRole("gridcell", { name: "25 December 2026" })).toHaveAttribute("aria-selected", "true");
    await user.click(screen.getByRole("gridcell", { name: "31 December 2026" }));
    expect(onSelect).toHaveBeenCalledWith("2026-12-31");
  });

  it("moves between months with the arrows", async () => {
    const user = userEvent.setup();
    render(<SetupCalendar value="2026-12-25" onSelect={() => {}} />);

    await user.click(screen.getByRole("button", { name: "Next month" }));
    expect(screen.getByText("January 2027")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Previous month" }));
    await user.click(screen.getByRole("button", { name: "Previous month" }));
    expect(screen.getByText("November 2026")).toBeInTheDocument();
  });

  it("can be driven from the keyboard: arrows by a day / week, Page Up / Down by a month, Enter to pick", async () => {
    const user = userEvent.setup();
    const onSelect = vi.fn();
    render(<SetupCalendar value="2026-12-25" onSelect={onSelect} autoFocus />);

    screen.getByRole("gridcell", { name: "25 December 2026" }).focus();
    await user.keyboard("{ArrowRight}");
    expect(screen.getByRole("gridcell", { name: "26 December 2026" })).toHaveFocus();
    await user.keyboard("{ArrowDown}");
    expect(screen.getByRole("gridcell", { name: "2 January 2027" })).toHaveFocus();
    expect(screen.getByText("January 2027")).toBeInTheDocument();
    await user.keyboard("{PageUp}");
    expect(screen.getByText("December 2026")).toBeInTheDocument();
    await user.keyboard("{ArrowLeft}");
    await user.keyboard("{Enter}");
    expect(onSelect).toHaveBeenCalledTimes(1);
  });

  it("dates before the minimum are disabled", async () => {
    const user = userEvent.setup();
    const onSelect = vi.fn();
    render(<SetupCalendar value="2026-12-15" min="2026-12-10" onSelect={onSelect} />);

    expect(screen.getByRole("gridcell", { name: "9 December 2026" })).toBeDisabled();
    expect(screen.getByRole("gridcell", { name: "10 December 2026" })).toBeEnabled();
    await user.click(screen.getByRole("gridcell", { name: "9 December 2026" }));
    expect(onSelect).not.toHaveBeenCalled();
  });
});

describe("SetupDatePicker", () => {
  it("shows the date, opens a calendar, closes on a pick and on Escape", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<SetupDatePicker id="d" value="2026-08-15" onChange={onChange} />);

    const trigger = screen.getByRole("button", { name: /15 Aug 2026/ });
    await user.click(trigger);
    expect(screen.getByRole("dialog", { name: "Choose a date" })).toBeInTheDocument();
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

    await user.click(trigger);
    await user.click(screen.getByRole("gridcell", { name: "20 August 2026" }));
    expect(onChange).toHaveBeenCalledWith("2026-08-20");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("shows the placeholder when nothing is chosen", () => {
    render(<SetupDatePicker id="d" value="" onChange={() => {}} placeholder="Select date" />);
    expect(screen.getByRole("button", { name: /Select date/ })).toBeInTheDocument();
  });
});
