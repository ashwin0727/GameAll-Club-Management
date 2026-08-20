import { describe, expect, it } from "vitest";
import { act, render, screen } from "@testing-library/react";
import { SaveStatus } from "@/features/onboarding/components/save-status";

describe("SaveStatus", () => {
  it("shows Saving immediately after the tracked value changes, then Saved", async () => {
    const { rerender } = render(<SaveStatus dirtyToken="a" delayMs={20} />);
    expect(screen.getByText("Saved")).toBeInTheDocument();

    rerender(<SaveStatus dirtyToken="b" delayMs={20} />);
    expect(screen.getByText("Saving…")).toBeInTheDocument();

    await act(() => new Promise((resolve) => setTimeout(resolve, 40)));
    expect(screen.getByText("Saved")).toBeInTheDocument();
  });
});
