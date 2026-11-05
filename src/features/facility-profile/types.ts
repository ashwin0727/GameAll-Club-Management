export type VenueType = "INDOOR" | "OUTDOOR";

export const VENUE_TYPE_OPTIONS: { value: VenueType; label: string; hint: string }[] = [
  { value: "INDOOR", label: "Indoor", hint: "Under a roof: halls, indoor courts" },
  { value: "OUTDOOR", label: "Outdoor", hint: "In the open: turfs, open courts" },
];

/** The five things a venue says it offers; each is simply on or off. */
export interface Amenities {
  parking: boolean;
  changingRooms: boolean;
  toilets: boolean;
  cafeteria: boolean;
  equipmentRental: boolean;
}

export const NO_AMENITIES: Amenities = { parking: false, changingRooms: false, toilets: false, cafeteria: false, equipmentRental: false };

export const AMENITY_OPTIONS: { key: keyof Amenities; label: string }[] = [
  { key: "parking", label: "Free Parking" },
  { key: "changingRooms", label: "Changing Rooms" },
  { key: "toilets", label: "Toilets / Rest Room" },
  { key: "cafeteria", label: "Cafeteria" },
  { key: "equipmentRental", label: "Equipment Rental" },
];

export type VerificationStatus = "PENDING" | "VERIFIED" | "REJECTED";

/** One uploaded facility photo and what GameAll's admin decided about it. */
export interface FacilityImage {
  id: string;
  url: string;
  sortOrder: number;
  status: VerificationStatus;
  note: string | null;
  createdAt: string;
}

export const MAX_FACILITY_PHOTOS = 8;
export const MAX_PHOTO_SIZE_BYTES = 8 * 1024 * 1024;
export const ACCEPTED_PHOTO_TYPES = ["image/jpeg", "image/png", "image/webp"];
