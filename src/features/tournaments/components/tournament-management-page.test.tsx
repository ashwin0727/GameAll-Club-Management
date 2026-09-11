import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { TournamentManagementPage } from "./tournament-management-page";
import { TournamentAppPreview } from "./tournament-app-preview";

describe("TournamentManagementPage", () => {
  it("renders the hero, the feature section and the why-separate section", () => {
    render(<TournamentManagementPage />);
    expect(screen.getByRole("heading", { level: 1, name: /Bigger Tournaments/i })).toBeInTheDocument();
    expect(screen.getByText(/Powered by GameAll/i)).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Everything You Need for Tournament Success" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Why a separate application?" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Already have the app?" })).toBeInTheDocument();
  });

  it("shows all five tournament feature cards", () => {
    render(<TournamentManagementPage />);
    for (const title of [
      "Create & Manage Tournaments",
      "Player & Team Registrations",
      "Fixtures & Scheduling",
      "Live Scores & Results",
      "Tournament Operations",
    ]) {
      expect(screen.getByRole("heading", { name: title })).toBeInTheDocument();
    }
  });

  it("explains when the app links are not configured instead of pointing anywhere fake", () => {
    render(<TournamentManagementPage />);
    // No env vars in the test environment → no CTA, a clear message instead.
    expect(screen.queryByRole("button", { name: /Open Tournament App/i })).not.toBeInTheDocument();
    expect(screen.getByText(/links aren't configured yet/i)).toBeInTheDocument();
  });

  it("has a back link to the dashboard", () => {
    render(<TournamentManagementPage />);
    expect(screen.getByRole("link", { name: /Back to Dashboard/i })).toHaveAttribute("href", "/dashboard");
  });
});

describe("TournamentAppPreview", () => {
  it("falls back to a labelled placeholder when there is no image", () => {
    render(<TournamentAppPreview images={[]} />);
    expect(screen.getByText("App preview coming soon")).toBeInTheDocument();
  });

  it("shows one image at a time with a dot control to switch", async () => {
    render(
      <TournamentAppPreview
        images={[
          { src: "/a.png", label: "Organizer home" },
          { src: "/b.png", label: "Tournament hub" },
        ]}
      />,
    );
    const imgs = screen.getAllByRole("img");
    expect(imgs).toHaveLength(1);
    expect(imgs[0]).toHaveAttribute("alt", expect.stringContaining("Organizer home"));

    await userEvent.click(screen.getByRole("tab", { name: "Show Tournament hub" }));
    expect(screen.getByRole("img")).toHaveAttribute("alt", expect.stringContaining("Tournament hub"));
  });
});
