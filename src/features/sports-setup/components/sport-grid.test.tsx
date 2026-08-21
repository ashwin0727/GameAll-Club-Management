import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SportGrid } from "@/features/sports-setup/components/sport-grid";
import { AVAILABLE_SPORTS } from "@/features/sports-setup/constants";

describe("SportGrid / SportCard", () => {
  it("renders every sport as a card with its name and description", () => {
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={vi.fn()} />);

    for (const sport of AVAILABLE_SPORTS) {
      expect(screen.getByText(sport.name)).toBeInTheDocument();
      expect(screen.getByText(sport.description)).toBeInTheDocument();
    }
  });

  it("marks selected cards with aria-checked=true and unselected ones false", () => {
    render(
      <SportGrid
        sports={AVAILABLE_SPORTS}
        selectedSportIds={["sport_badminton"]}
        onToggle={vi.fn()}
      />,
    );

    expect(screen.getByRole("checkbox", { name: /Badminton/ })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("checkbox", { name: /Cricket/ })).toHaveAttribute("aria-checked", "false");
  });

  it("toggles a sport when the whole card is clicked, not just an inner checkbox", async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={onToggle} />);

    await user.click(screen.getByText("Indoor racket sport"));

    expect(onToggle).toHaveBeenCalledWith("sport_badminton");
  });

  it("is keyboard-operable via Enter on a focused card", async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={[]} onToggle={onToggle} />);

    screen.getByRole("checkbox", { name: /Tennis/ }).focus();
    await user.keyboard("{Enter}");

    expect(onToggle).toHaveBeenCalledWith("sport_tennis");
  });
});