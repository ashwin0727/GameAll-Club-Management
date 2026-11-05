import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { ACCEPTED_PHOTO_TYPES, MAX_PHOTO_SIZE_BYTES, type FacilityImage, type VerificationStatus } from "@/features/facility-profile/types";

// facility_images and the facility-photos bucket are newer than the generated database types, hence the loose client.
type Loose = SupabaseClient<any, "public", any>; // eslint-disable-line @typescript-eslint/no-explicit-any

function extensionOf(file: File): string {
  const fromType = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file.type];
  return fromType ?? "jpg";
}

/** Why [file] can't be used as a facility photo, or null when it can. */
export function photoProblem(file: File): string | null {
  if (!ACCEPTED_PHOTO_TYPES.includes(file.type)) return "Upload a JPG, PNG or WebP image.";
  if (file.size > MAX_PHOTO_SIZE_BYTES) return "Each photo must be smaller than 8 MB.";
  return null;
}

interface ImageRow {
  id: string;
  url: string;
  sort_order: number;
  verification_status: VerificationStatus;
  verification_note: string | null;
  created_at: string;
}

const toImage = (r: ImageRow): FacilityImage => ({
  id: r.id,
  url: r.url,
  sortOrder: r.sort_order,
  status: r.verification_status,
  note: r.verification_note,
  createdAt: r.created_at,
});

/** The facility's photos and the owner's own uploads: stored in the owner's folder of the public facility-photos bucket. */
export class FacilityPhotos {
  private readonly supabase: Loose;

  constructor(client?: unknown) {
    this.supabase = (client ?? createClient()) as Loose;
  }

  /** Uploads [file] for the signed-in owner and returns its public URL. */
  async upload(userId: string, file: File): Promise<string> {
    const problem = photoProblem(file);
    if (problem) throw new Error(problem);
    const path = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${extensionOf(file)}`;
    const { error } = await this.supabase.storage.from("facility-photos").upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw new Error("We couldn't upload a photo. Please try again.");
    return this.supabase.storage.from("facility-photos").getPublicUrl(path).data.publicUrl as string;
  }

  /** Uploads every file and attaches them to the facility (they start waiting for the admin's check). Cover = the first. */
  async addAll(facilityId: string, userId: string, files: File[]): Promise<void> {
    const urls: string[] = [];
    for (const file of files) urls.push(await this.upload(userId, file));
    if (urls.length === 0) return;
    const { error } = await this.supabase.from("facility_images").insert(urls.map((url, i) => ({ facility_id: facilityId, url, sort_order: i })));
    if (error) throw new Error("We couldn't save your photos. Please try again.");
  }

  async list(facilityId: string): Promise<FacilityImage[]> {
    const { data, error } = await this.supabase
      .from("facility_images")
      .select("id, url, sort_order, verification_status, verification_note, created_at")
      .eq("facility_id", facilityId)
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true });
    if (error) throw new Error("We couldn't load your photos.");
    return ((data ?? []) as ImageRow[]).map(toImage);
  }

  async remove(imageId: string): Promise<void> {
    const { error } = await this.supabase.from("facility_images").delete().eq("id", imageId);
    if (error) throw new Error("We couldn't remove that photo. Please try again.");
  }
}
