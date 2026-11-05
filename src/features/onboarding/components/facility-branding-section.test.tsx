import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FacilityBrandingSection } from "@/features/onboarding/components/facility-branding-section";

const props = { logo: null, onLogoChange: vi.fn(), photos: [] as File[], onPhotosChange: vi.fn() };

describe("FacilityBrandingSection", () => {
  it("renders the optional logo upload", () => {
    render(<FacilityBrandingSection {...props} />);
    expect(screen.getByText("+ Upload Logo")).toBeInTheDocument();
    expect(screen.getByText(/Optional/)).toBeInTheDocument();
  });

  it("no longer has the About Your Facility box", () => {
    render(<FacilityBrandingSection {...props} />);
    expect(screen.queryByLabelText("About Your Facility")).not.toBeInTheDocument();
  });

  it("asks for at least one photo and passes the chosen ones up", async () => {
    const user = userEvent.setup();
    const onPhotosChange = vi.fn();
    render(<FacilityBrandingSection {...props} onPhotosChange={onPhotosChange} />);

    expect(screen.getByText(/at least one clear photo/i)).toBeInTheDocument();
    const file = new File(["x"], "court.jpg", { type: "image/jpeg" });
    await user.upload(screen.getByLabelText("Facility Photos"), file);
    expect(onPhotosChange).toHaveBeenCalledWith([file]);
  });

  it("refuses a file that is not a picture", async () => {
    const user = userEvent.setup({ applyAccept: false });
    const onPhotosChange = vi.fn();
    render(<FacilityBrandingSection {...props} onPhotosChange={onPhotosChange} />);

    await user.upload(screen.getByLabelText("Facility Photos"), new File(["x"], "notes.pdf", { type: "application/pdf" }));
    expect(await screen.findByText("Upload a JPG, PNG or WebP image.")).toBeInTheDocument();
    expect(onPhotosChange).toHaveBeenCalledWith([]);
  });

  it("shows a chosen photo with a remove button, and the first one as the cover", async () => {
    const user = userEvent.setup();
    const onPhotosChange = vi.fn();
    const file = new File(["x"], "a.jpg", { type: "image/jpeg" });
    render(<FacilityBrandingSection {...props} photos={[file]} onPhotosChange={onPhotosChange} />);

    expect(screen.getByText("Cover")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /Remove new photo 1/ }));
    expect(onPhotosChange).toHaveBeenCalledWith([]);
  });
});
