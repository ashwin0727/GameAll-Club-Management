import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { CoachAvailabilityEditor, validateAvailabilityWindows } from "@/features/coaching/components/coach-availability-editor";

const mon = { dayOfWeek: 1, startTime: "09:00", endTime: "12:00" };

describe("CoachAvailabilityEditor", () => {
  it("says so straight away when the same day and time is added twice", () => {
    render(<CoachAvailabilityEditor windows={[mon, { ...mon }]} onChange={vi.fn()} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Mon 09:00–12:00 is added twice");
  });

  it("names both slots when two on the same day overlap", () => {
    render(<CoachAvailabilityEditor windows={[mon, { dayOfWeek: 1, startTime: "11:00", endTime: "13:00" }]} onChange={vi.fn()} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Mon 09:00–12:00 overlaps Mon 11:00–13:00");
  });

  it("shows no message for different days or back-to-back slots", () => {
    render(<CoachAvailabilityEditor windows={[mon, { dayOfWeek: 2, startTime: "09:00", endTime: "12:00" }, { dayOfWeek: 1, startTime: "12:00", endTime: "14:00" }]} onChange={vi.fn()} />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("a slot ending before it starts is flagged on its own row", () => {
    render(<CoachAvailabilityEditor windows={[{ dayOfWeek: 1, startTime: "10:00", endTime: "09:00" }]} onChange={vi.fn()} />);
    expect(screen.getByText("The end time must be after the start time.")).toBeInTheDocument();
  });

  it("Add Window picks a day that has no slot yet", () => {
    const onChange = vi.fn();
    render(<CoachAvailabilityEditor windows={[mon]} onChange={onChange} />);
    screen.getByRole("button", { name: /Add Window/ }).click();
    expect(onChange).toHaveBeenCalledWith([mon, { dayOfWeek: 2, startTime: "16:00", endTime: "20:00" }]);
  });

  it("validateAvailabilityWindows (used by the coach profile) rejects duplicates too", () => {
    expect(validateAvailabilityWindows([mon, { ...mon }])).toMatch(/added twice/);
    expect(validateAvailabilityWindows([{ dayOfWeek: 1, startTime: "10:00", endTime: "09:00" }])).toMatch(/end time must be after/);
    expect(validateAvailabilityWindows([mon])).toBeNull();
  });
});
