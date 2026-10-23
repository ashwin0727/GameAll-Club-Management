import { describe, expect, it } from "vitest";
import { useState } from "react";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { PageAccessMatrix } from "@/features/staff/components/page-access-matrix";

function Harness({ initial = [] as string[], onKeys, canGrant = () => true }: { initial?: string[]; onKeys: (k: Set<string>) => void; canGrant?: (k: string) => boolean }) {
  const [selected, setSelected] = useState(new Set(initial));
  return (
    <PageAccessMatrix
      selected={selected}
      canGrant={canGrant}
      onChange={(n) => {
        setSelected(n);
        onKeys(n);
      }}
    />
  );
}

function row(label: string) {
  const heading = screen.getByText(label);
  return within(heading.closest("li") as HTMLElement);
}

describe("PageAccessMatrix", () => {
  it("lists every page with None / View / Edit, and View grants only the View keys", async () => {
    const user = userEvent.setup();
    let keys = new Set<string>();
    render(<Harness onKeys={(k) => (keys = k)} />);

    await user.click(row("Guest Players").getByRole("radio", { name: /View/ }));
    expect(keys.has("GUEST_PLAYERS_VIEW")).toBe(true);
    expect(keys.has("GUEST_PLAYERS_EDIT")).toBe(false);

    await user.click(row("Guest Players").getByRole("radio", { name: /Edit/ }));
    expect(keys.has("GUEST_PLAYERS_EDIT")).toBe(true);

    await user.click(row("Guest Players").getByRole("radio", { name: /None/ }));
    expect(keys.has("GUEST_PLAYERS_VIEW")).toBe(false);
  });

  it("labels Home as Today for the mobile app and offers no Edit on a view-only page", () => {
    render(<Harness onKeys={() => undefined} />);
    expect(screen.getByText("Home (Today in the mobile app)")).toBeInTheDocument();
    expect(within(screen.getByText("Home (Today in the mobile app)").closest("li") as HTMLElement).queryByRole("radio", { name: /Edit/ })).toBeNull();
  });

  it("report pages say 'Edit (can export)'", () => {
    render(<Harness onKeys={() => undefined} />);
    expect(row("Revenue Report").getByRole("radio", { name: /can export/ })).toBeInTheDocument();
  });

  it("disables levels the editor is not allowed to grant", () => {
    render(<Harness onKeys={() => undefined} canGrant={(k) => k !== "GUEST_PLAYERS_EDIT"} />);
    expect(row("Guest Players").getByRole("radio", { name: /Edit/ })).toBeDisabled();
    expect(row("Guest Players").getByRole("radio", { name: /View/ })).not.toBeDisabled();
  });

  it("the coach switch adds the restriction key", async () => {
    const user = userEvent.setup();
    let keys = new Set<string>();
    render(<Harness onKeys={(k) => (keys = k)} />);
    await user.click(screen.getByRole("switch", { name: /Limit coaching/ }));
    expect(keys.has("COACHING_OWN_ONLY")).toBe(true);
  });

  it("shows extras only once the page is reachable", async () => {
    const user = userEvent.setup();
    render(<Harness onKeys={() => undefined} />);
    expect(screen.queryByText(/contact details on bookings/)).toBeNull();
    await user.click(row("Calendar").getByRole("radio", { name: /View/ }));
    expect(screen.getByText(/contact details on bookings/)).toBeInTheDocument();
  });
});
