/** What the public Pricing page says about each module, per plan. `null` = not in the plan. */
export interface PricingLine {
  title: string;
  /** The qualifier shown under the title, e.g. "Incl. Plan & Schedule". */
  sub?: string;
  description: string;
}

export interface PricingModule {
  key: string;
  /** Name used in the comparison table. */
  label: string;
  basic: PricingLine | null;
  advanced: PricingLine | null;
}

export const PRICES = {
  basic: { month: 129, year: 1299 },
  advanced: { month: 199, year: 1999 },
} as const;

const HOME: PricingLine = {
  title: "Today / Home",
  description:
    "Your club at a glance: today's bookings, collections, pending payments and what needs your attention, the moment you sign in.",
};
const CALENDAR: PricingLine = {
  title: "Calendar",
  description:
    "A live court calendar for every day: see what is booked, free or blocked, and create, move or cancel a booking in a tap.",
};
const TOURNAMENTS: PricingLine = {
  title: "Tournaments Management",
  description:
    "Run tournaments end to end: registrations, draws, live scores and brackets, with the result page ready to share.",
};
const GUEST_BOOKING: PricingLine = {
  title: "Guest Booking",
  description:
    "Take walk-in and online bookings from players who are not members, with advance payments, refunds and receipts.",
};
const REPORTS: PricingLine = {
  title: "Reports & Analytics",
  description: "See what is working: bookings, revenue, court utilisation and peak hours, with exports for your records.",
};

export const PRICING_MODULES: PricingModule[] = [
  { key: "home", label: "Today / Home", basic: HOME, advanced: HOME },
  { key: "calendar", label: "Calendar", basic: CALENDAR, advanced: CALENDAR },
  { key: "tournaments", label: "Tournaments Management", basic: TOURNAMENTS, advanced: TOURNAMENTS },
  { key: "guest-booking", label: "Guest Booking", basic: GUEST_BOOKING, advanced: GUEST_BOOKING },
  {
    key: "guest-players",
    label: "Guest Player Lists",
    basic: null,
    advanced: {
      title: "Guest Player Lists",
      description:
        "A searchable list of every guest who has booked with you, with their booking history and contact details for repeat business.",
    },
  },
  {
    key: "player-app",
    label: "Player App",
    basic: {
      title: "Player App",
      sub: "Guest booking only",
      description: "Your club is visible in the GameAll Player App, and players can book guest slots with you. Memberships are not open to players.",
    },
    advanced: {
      title: "Player App",
      sub: "Guest booking & membership enrolment",
      description: "Your club is visible in the GameAll Player App. Players can book guest slots and enrol in your memberships themselves.",
    },
  },
  {
    key: "memberships",
    label: "Memberships",
    basic: {
      title: "Memberships",
      sub: "Manual Payment Tracking · Incl. Plan & Schedule",
      description:
        "Create membership plans, enrol members and schedule their sessions. You record each payment yourself as it comes in.",
    },
    advanced: {
      title: "Memberships",
      sub: "Automatic Payment Tracking · Incl. Plan & Schedule",
      description:
        "Create plans, enrol members and schedule sessions. Members pay by Auto Pay, and every cycle is collected and tracked for you.",
    },
  },
  {
    key: "coaching",
    label: "Coaching",
    basic: {
      title: "Coaching",
      sub: "Manual Payment Tracking · Incl. Program & Students",
      description: "Set up coaching programs and enrol students. You record each fee payment yourself.",
    },
    advanced: {
      title: "Coaching",
      sub: "Automatic Payment Tracking · Incl. Program, Students & Schedule",
      description:
        "Programs, students and the full session schedule, with monthly fees collected automatically through Auto Pay.",
    },
  },
  {
    key: "maintenance",
    label: "Maintenance Management",
    basic: null,
    advanced: {
      title: "Maintenance Management",
      description:
        "Block courts for repairs and upkeep, schedule recurring maintenance and track what each job costs, so bookings never clash with work.",
    },
  },
  {
    key: "staff",
    label: "Staff Management",
    basic: null,
    advanced: {
      title: "Staff Management",
      description:
        "Add your team, create roles such as Front Desk or Coach, and decide page by page who can see or change what.",
    },
  },
  {
    key: "finance",
    label: "Finance Management",
    basic: null,
    advanced: {
      title: "Finance Management",
      description:
        "Every payment and expense in one place, with daily closing and profit and loss, so you always know where the club stands.",
    },
  },
  { key: "reports", label: "Reports & Analytics", basic: REPORTS, advanced: REPORTS },
  {
    key: "payouts",
    label: "Payout speed",
    basic: {
      title: "Next-Day Payouts (T+1)",
      description: "Money collected online reaches your bank account on the next working day.",
    },
    advanced: {
      title: "Fast Payouts (within 5 minutes)",
      description: "Money collected online reaches your bank account within minutes, not the next day.",
    },
  },
];

export const PLAN_BLURB = {
  basic: "Everything you need to take bookings, run memberships and coaching, and track payments yourself.",
  advanced: "The full system: automatic payment collection, finance, staff, maintenance and the fastest payouts.",
} as const;
