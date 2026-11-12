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

/** The 12 amenities a venue can say it offers (stored as keys in facilities.amenity_keys). */
export const FACILITY_AMENITIES = [
  { key: "car_parking", label: "Car Parking" },
  { key: "two_wheeler_parking", label: "Two-Wheeler Parking" },
  { key: "restroom", label: "Restroom" },
  { key: "changing_room", label: "Changing Room" },
  { key: "shower", label: "Shower" },
  { key: "drinking_water", label: "Drinking Water" },
  { key: "seating_area", label: "Seating Area" },
  { key: "cafeteria", label: "Cafeteria / Food" },
  { key: "wifi", label: "Wi-Fi" },
  { key: "lockers", label: "Lockers" },
  { key: "equipment_rental", label: "Equipment Rental" },
  { key: "first_aid", label: "First Aid" },
] as const;

export type AmenityKey = (typeof FACILITY_AMENITIES)[number]["key"];
export const AMENITY_KEYS = FACILITY_AMENITIES.map((a) => a.key) as [AmenityKey, ...AmenityKey[]];
export const MAX_CUSTOM_AMENITIES = 10;

export type OwnershipType = "OWNED" | "LEASED";
export const OWNERSHIP_OPTIONS: { value: OwnershipType; label: string }[] = [
  { value: "OWNED", label: "Owned" },
  { value: "LEASED", label: "Leased" },
];

/** The five switches under "Facility Policies" (stored as boolean columns on facilities). */
export interface FacilityPolicies {
  allowOnlineBooking: boolean;
  allowWalkIn: boolean;
  advancePaymentRequired: boolean;
  allowCancellations: boolean;
  requirePlayerDetails: boolean;
}

export const DEFAULT_POLICIES: FacilityPolicies = {
  allowOnlineBooking: true,
  allowWalkIn: true,
  advancePaymentRequired: false,
  allowCancellations: true,
  requirePlayerDetails: true,
};

export const POLICY_OPTIONS: { key: keyof FacilityPolicies; label: string; hint: string }[] = [
  { key: "allowOnlineBooking", label: "Allow Online Booking", hint: "Players can book your courts from the GameAll Player app." },
  { key: "allowWalkIn", label: "Allow Walk-in / Offline Booking", hint: "Your front desk can take bookings for players who walk in." },
  { key: "advancePaymentRequired", label: "Advance Payment Required", hint: "Players must pay in advance to confirm a booking." },
  { key: "allowCancellations", label: "Allow Cancellations", hint: "Players can cancel a booking, subject to your refund rules." },
  { key: "requirePlayerDetails", label: "Require Player Details", hint: "Ask for the player's name and phone number when booking." },
];

export const CONTACT_ROLE_OPTIONS = ["Facility Owner", "Manager", "Receptionist", "Coach", "Other"] as const;
