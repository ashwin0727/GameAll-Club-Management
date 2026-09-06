import { authed, closeAll, makeFacility, makeOpenCourt, makeUser, resetCore, superuser } from "./_helpers.ts";

// Every Reports & Analytics RPC (migrations 0056–0063), called against a
// real facility with the parameter shape the web/Flutter clients send.
// Catches PL/pgSQL runtime faults (ambiguous columns, bad casts, missing
// deps) that pure-logic and source-contract tests cannot — the whole
// reason these functions kept reaching production broken.
//
// The assertion is simply "it returns without raising".

const SCOPED = "($1,'THIS_MONTH',null,null,null,null)"; // facility, preset, start, end, sport, court
const DATE_ONLY = "($1,'THIS_MONTH',null,null)"; // facility, preset, start, end

const CALLS: Array<{ sql: string; note: string }> = [
  { sql: `select * from get_booking_analytics${SCOPED}`, note: "bookings report" },
  { sql: `select * from get_booking_trend($1,'THIS_MONTH',null,null,null,null,'daily')`, note: "bookings trend" },
  { sql: `select * from get_bookings_by_sport${SCOPED}`, note: "bookings by sport" },
  { sql: `select * from get_booking_source_split${SCOPED}`, note: "booking source split" },

  { sql: `select * from get_court_utilization${SCOPED}`, note: "court utilization" },
  { sql: `select * from get_sport_utilization${SCOPED}`, note: "sport utilization" },
  { sql: `select * from get_overall_utilization${SCOPED}`, note: "overall utilization" },
  { sql: `select * from get_peak_hours${SCOPED}`, note: "peak hours" },
  { sql: `select * from get_demand_heatmap${SCOPED}`, note: "demand heatmap" },

  { sql: `select * from get_revenue_by_sport${SCOPED}`, note: "revenue by sport" },
  { sql: `select * from get_revenue_by_court${SCOPED}`, note: "revenue by court" },

  { sql: `select * from get_membership_analytics${DATE_ONLY}`, note: "membership analytics" },
  { sql: `select * from get_memberships_by_type${DATE_ONLY}`, note: "memberships by type" },
  { sql: `select * from get_membership_session_analytics${SCOPED}`, note: "membership session analytics" },
  { sql: `select * from get_guest_release_analytics${SCOPED}`, note: "guest release analytics" },

  { sql: `select * from get_analytics_overview${SCOPED}`, note: "analytics overview" },

  { sql: `select * from get_guest_booking_analytics${SCOPED}`, note: "guest booking analytics" },
  { sql: `select * from get_guest_bookings_by_sport${SCOPED}`, note: "guest bookings by sport" },
  { sql: `select * from get_guest_bookings_by_court${SCOPED}`, note: "guest bookings by court" },
  { sql: `select * from get_guest_peak_hours${SCOPED}`, note: "guest peak hours" },
];

Deno.test("every analytics RPC runs without raising", async () => {
  const su = await superuser();
  await resetCore(su);
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  await makeOpenCourt(su, facilityId);
  await su.queryArray({
    text: `insert into membership_plans (facility_id, name, price_inr, duration_days)
           values ($1, 'Smoke Plan', 1000, 30)`,
    args: [facilityId],
  });

  const c = await authed(owner);
  const failures: string[] = [];
  for (const call of CALLS) {
    try {
      await c.queryArray({ text: call.sql, args: [facilityId] });
    } catch (err) {
      failures.push(`${call.note}: ${String(err)}`);
    }
  }

  await closeAll(su, c);
  if (failures.length) {
    throw new Error(`analytics RPCs raised:\n  - ${failures.join("\n  - ")}`);
  }
});
