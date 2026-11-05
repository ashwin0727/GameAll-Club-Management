import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AmenitiesSection } from "@/features/facility-profile/components/amenities-section";
import { VenueTypeField } from "@/features/facility-profile/components/venue-type-field";
import { NO_AMENITIES } from "@/features/facility-profile/types";

describe("AmenitiesSection", () => {
  it("lists exactly the five amenities, each off by default", () => {
    render(<AmenitiesSection value={NO_AMENITIES} onChange={vi.fn()} />);
    const names = screen.getAllByRole("switch").map((s) => s.getAttribute("aria-label"));
    expect(names).toEqual(["Free Parking", "Changing Rooms", "Toilets / Rest Room", "Cafeteria", "Equipment Rental"]);
    screen.getAllByRole("switch").forEach((s) => expect(s).toHaveAttribute("aria-checked", "false"));
  });

  it("flips only the toggle that was clicked", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<AmenitiesSection value={{ ...NO_AMENITIES, cafeteria: true }} onChange={onChange} />);
    expect(screen.getByRole("switch", { name: "Cafeteria" })).toHaveAttribute("aria-checked", "true");

    await user.click(screen.getByRole("switch", { name: "Free Parking" }));
    expect(onChange).toHaveBeenCalledWith({ ...NO_AMENITIES, cafeteria: true, parking: true });
    await user.click(screen.getByRole("switch", { name: "Cafeteria" }));
    expect(onChange).toHaveBeenLastCalledWith({ ...NO_AMENITIES, cafeteria: false });
  });

  it("works from the keyboard", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<AmenitiesSection value={NO_AMENITIES} onChange={onChange} />);
    await user.tab();
    await user.keyboard("{Enter}");
    expect(onChange).toHaveBeenCalledWith({ ...NO_AMENITIES, parking: true });
  });
});

describe("VenueTypeField", () => {
  it("offers exactly Indoor and Outdoor", () => {
    render(<VenueTypeField value={undefined} onChange={vi.fn()} />);
    expect(screen.getAllByRole("radio").map((r) => r.textContent?.split(/(?=[A-Z][a-z]+ )/)[0]?.trim())).toHaveLength(2);
    expect(screen.getByRole("radio", { name: /Indoor/ })).toHaveAttribute("aria-checked", "false");
    expect(screen.getByRole("radio", { name: /Outdoor/ })).toHaveAttribute("aria-checked", "false");
  });

  it("selects one and reports it", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<VenueTypeField value="INDOOR" onChange={onChange} />);
    expect(screen.getByRole("radio", { name: /Indoor/ })).toHaveAttribute("aria-checked", "true");
    await user.click(screen.getByRole("radio", { name: /Outdoor/ }));
    expect(onChange).toHaveBeenCalledWith("OUTDOOR");
  });

  it("shows an error", () => {
    render(<VenueTypeField value={undefined} onChange={vi.fn()} error="Choose indoor or outdoor" />);
    expect(screen.getByRole("alert")).toHaveTextContent("Choose indoor or outdoor");
  });
});
