import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FileUpload } from "@/components/shared/file-upload";

function makeFile(name: string, type: string, sizeBytes: number): File {
  const file = new File([new Uint8Array(sizeBytes)], name, { type });
  return file;
}

describe("FileUpload", () => {
  it("shows the upload prompt when empty", () => {
    render(<FileUpload label="Facility Logo" value={null} onChange={vi.fn()} />);
    expect(screen.getByText("+ Upload Logo")).toBeInTheDocument();
  });

  it("accepts a valid PNG under the size limit", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const file = makeFile("logo.png", "image/png", 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), file);

    expect(onChange).toHaveBeenCalledWith(file);
  });

  it("rejects a file over 5MB with an inline message", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const tooBig = makeFile("logo.png", "image/png", 6 * 1024 * 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), tooBig);

    expect(onChange).not.toHaveBeenCalled();
    expect(await screen.findByText(/must be smaller than 5MB/i)).toBeInTheDocument();
  });

  it("rejects an unsupported file type", async () => {
    const user = userEvent.setup({ applyAccept: false });
    const onChange = vi.fn();
    render(<FileUpload label="Facility Logo" value={null} onChange={onChange} />);

    const badType = makeFile("logo.gif", "image/gif", 1024);
    await user.upload(screen.getByLabelText("Facility Logo"), badType);

    expect(onChange).not.toHaveBeenCalled();
    expect(await screen.findByText(/PNG, JPG, JPEG or WebP/i)).toBeInTheDocument();
  });

  it("shows Replace and Remove once a file is set, and Remove clears it", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    const file = makeFile("logo.png", "image/png", 1024);
    render(<FileUpload label="Facility Logo" value={file} onChange={onChange} />);

    expect(screen.getByRole("button", { name: "Replace" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Remove" }));

    expect(onChange).toHaveBeenCalledWith(null);
  });
});
