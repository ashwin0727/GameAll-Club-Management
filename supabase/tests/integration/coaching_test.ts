import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import {
  authed,
  closeAll,
  makeFacility,
  makeOpenCourt,
  makeUser,
  resetCore,
  superuser,
} from "./_helpers.ts";

// Coaching Management (migrations 0082-0087) — the spec's required tests
// (§74-§78). Coach/program/session/enrollment lifecycle, conflict detection
// (coach / court / booking / maintenance), capacity + concurrency, the
// obligation-vs-revenue separation, membership-included pricing, RLS
// facility isolation, and the permission gates.

type SU = Awaited<ReturnType<typeof superuser>>;
type C = Awaited<ReturnType<typeof authed>>;

/** Tomorrow, `h`:00 in Asia/Kolkata (== h-5:30 UTC), as a UTC ISO string. */
function ist(h: number, m = 0): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  // IST is UTC+5:30
  const totalMin = h * 60 + m - (5 * 60 + 30);
  return new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0) +
      totalMin * 60_000,
  )
    .toISOString();
}

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(
    `delete from coaching_events;
     delete from student_progress_notes;
     delete from coaching_session_students;
     delete from coaching_sessions;
     delete from coaching_enrollments;
     delete from coach_availability_exceptions;
     delete from coach_availability;
     delete from coaches;
     delete from coaching_programs;
     delete from members;`,
  );
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  const { courtId } = await makeOpenCourt(su, facilityId);
  return { owner, facilityId, courtId };
}

async function addStaff(
  su: SU,
  facilityId: string,
  userId: string,
  role: "owner" | "manager" | "staff",
) {
  await su.queryArray({
    text:
      `insert into facility_users (facility_id, user_id, role, status, is_primary, activated_at)
           values ($1, $2, $3, 'ACTIVE', false, now())`,
    args: [facilityId, userId, role],
  });
}

/** A facility-scoped custom role with exactly `keys`, assigned to a new user. */
async function userWithPerms(
  su: SU,
  facilityId: string,
  keys: string[],
): Promise<string> {
  const uid = await makeUser(su);
  const roleId = crypto.randomUUID();
  await su.queryArray({
    text:
      `insert into roles (id, facility_id, key, base_role, name, is_system, is_template)
           values ($1, $2, null, 'staff', $3, false, false)`,
    args: [roleId, facilityId, `role-${roleId.slice(0, 8)}`],
  });
  for (const k of keys) {
    await su.queryArray({
      text:
        `insert into role_permissions (role_id, permission_key) values ($1, $2)`,
      args: [roleId, k],
    });
  }
  await su.queryArray({
    text:
      `insert into facility_users (facility_id, user_id, role, role_id, status, is_primary, activated_at)
           values ($1, $2, 'staff', $3, 'ACTIVE', false, now())`,
    args: [facilityId, uid, roleId],
  });
  return uid;
}

async function makeMember(
  su: SU,
  facilityId: string,
  name = "Arun Sharma",
): Promise<string> {
  const id = crypto.randomUUID();
  await su.queryArray({
    text: `insert into members (id, facility_id, full_name, phone)
           values ($1, $2, $3, $4)`,
    args: [
      id,
      facilityId,
      name,
      `9${Math.floor(Math.random() * 1e9).toString().padStart(9, "0")}`,
    ],
  });
  return id;
}

async function coach(
  c: C,
  facilityId: string,
  userId: string,
): Promise<string> {
  const id = (
    await c.queryObject<{ id: string }>({
      text:
        `select (add_coach($1, $2, 'Beginner', 5, null, null, 80000, 'ACTIVE', null)).id as id`,
      args: [facilityId, userId],
    })
  ).rows[0].id;
  // Available every day, all day, so any test slot passes coach_is_available.
  await c.queryArray({
    text: `select set_coach_availability($1, $2::jsonb)`,
    args: [
      id,
      JSON.stringify(
        [0, 1, 2, 3, 4, 5, 6].map((d) => ({
          dayOfWeek: d,
          startTime: "00:00",
          endTime: "23:59",
        })),
      ),
    ],
  });
  return id;
}

async function program(
  c: C,
  facilityId: string,
  opts: {
    name?: string;
    price?: number | null;
    capacity?: number;
    included?: boolean;
  } = {},
): Promise<string> {
  return (
    await c.queryObject<{ id: string }>({
      text:
        `select (create_coaching_program($1, $2, 'Beginner', 'All Ages', 'Group', null, null, 60, $3, 8, $4, $5)).id as id`,
      args: [
        facilityId,
        opts.name ?? "Beginner Group",
        opts.capacity ?? 10,
        opts.price === undefined ? 300000 : opts.price,
        opts.included ?? false,
      ],
    })
  ).rows[0].id;
}

async function enrollment(
  c: C,
  facilityId: string,
  memberId: string,
  programId: string,
  price: number | null = null,
): Promise<string> {
  return (
    await c.queryObject<{ id: string }>({
      text:
        `select (create_coaching_enrollment($1, $2, $3, null, null, null, null, $4, null, null)).id as id`,
      args: [facilityId, memberId, programId, price],
    })
  ).rows[0].id;
}

async function session(
  c: C,
  facilityId: string,
  programId: string,
  coachId: string,
  courtId: string,
  startH: number,
  endH: number,
  capacity: number | null = null,
): Promise<string> {
  return (
    await c.queryObject<{ id: string }>({
      text:
        `select (create_coaching_session($1,$2,$3,$4,$5,$6,$7,null,null,'SCHEDULED',false)).id as id`,
      args: [
        facilityId,
        programId,
        coachId,
        courtId,
        ist(startH),
        ist(endH),
        capacity,
      ],
    })
  ).rows[0].id;
}

// ── Coaches ─────────────────────────────────────────────────────────────────
Deno.test("coach: added onto an existing staff member; a non-staff user is rejected", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);

  const staffUser = await makeUser(su);
  await addStaff(su, facilityId, staffUser, "staff");
  const coachId = await coach(c, facilityId, staffUser);
  assert(coachId);

  const outsider = await makeUser(su);
  await assertRejects(
    () =>
      c.queryArray({
        text: `select add_coach($1, $2)`,
        args: [facilityId, outsider],
      }),
    Error,
    "not an active staff member",
  );
  await closeAll(su, c);
});

Deno.test("coach: one profile per staff member per facility (duplicate rejected)", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  await coach(c, facilityId, u);
  await assertRejects(
    () =>
      c.queryArray({ text: `select add_coach($1, $2)`, args: [facilityId, u] }),
    Error,
    "already has a coaching profile",
  );
  await closeAll(su, c);
});

Deno.test("coach: deactivating keeps the row; a deactivated coach can't take a session", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);

  await c.queryArray({
    text:
      `select update_coach($1, null, null, null, null, null, 'INACTIVE', null)`,
    args: [coachId],
  });
  const still = await su.queryObject<{ n: bigint }>({
    text: `select count(*)::bigint n from coaches where id=$1`,
    args: [coachId],
  });
  assertEquals(Number(still.rows[0].n), 1);

  await assertRejects(
    () => session(c, facilityId, p, coachId, courtId, 10, 11),
    Error,
    "not active",
  );
  await closeAll(su, c);
});

// ── Programs ────────────────────────────────────────────────────────────────
Deno.test("program: create / edit / deactivate; duplicate name in a facility is rejected", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const p = await program(c, facilityId, { name: "Kids U12" });
  await c.queryArray({
    text: `select update_coaching_program($1, 'Kids Under 12')`,
    args: [p],
  });
  await c.queryArray({
    text:
      `select update_coaching_program($1, null, null, null, null, null, null, null, null, null, null, null, 'INACTIVE')`,
    args: [p],
  });
  const row = await su.queryObject<{ status: string; name: string }>({
    text: `select status, name from coaching_programs where id=$1`,
    args: [p],
  });
  assertEquals(row.rows[0].status, "INACTIVE");

  await assertRejects(
    () =>
      c.queryArray({
        text: `select create_coaching_program($1, 'kids under 12')`,
        args: [facilityId],
      }),
    Error,
    "already exists",
  );
  await closeAll(su, c);
});

// ── Sessions & conflict detection (§9-§13) ──────────────────────────────────
Deno.test("session: a second session for the same coach at an overlapping time is rejected", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const { courtId: court2 } = await makeOpenCourt(su, facilityId);
  const p = await program(c, facilityId);

  await session(c, facilityId, p, coachId, courtId, 16, 17);
  await assertRejects(
    () => session(c, facilityId, p, coachId, court2, 16, 17), // different court, same coach/time
    Error,
    "already has a session",
  );
  await closeAll(su, c);
});

Deno.test("session: a second session on the same court at an overlapping time is rejected", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u1 = await makeUser(su);
  await addStaff(su, facilityId, u1, "staff");
  const u2 = await makeUser(su);
  await addStaff(su, facilityId, u2, "staff");
  const c1 = await coach(c, facilityId, u1);
  const c2 = await coach(c, facilityId, u2);
  const p = await program(c, facilityId);

  await session(c, facilityId, p, c1, courtId, 16, 18);
  await assertRejects(
    () => session(c, facilityId, p, c2, courtId, 17, 19), // same court, different coach
    Error,
    "already uses this court",
  );
  await closeAll(su, c);
});

Deno.test("session: an existing booking on the court/time blocks the session, and vice-versa (§10 / §50)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);

  // booking first → session rejected
  await c.queryArray({
    text:
      `select create_booking($1,$2,$3,$4,'GUEST',null,'Walk-in',null,null,'PENDING',null,1,null)`,
    args: [facilityId, courtId, ist(16), ist(17)],
  });
  await assertRejects(
    () => session(c, facilityId, p, coachId, courtId, 16, 17),
    Error,
    "already booked",
  );

  // session first (different slot) → booking on that slot rejected
  await session(c, facilityId, p, coachId, courtId, 18, 19);
  await assertRejects(
    () =>
      c.queryArray({
        text:
          `select create_booking($1,$2,$3,$4,'GUEST',null,'Walk-in',null,null,'PENDING',null,1,null)`,
        args: [facilityId, courtId, ist(18, 30), ist(19)],
      }),
    Error,
    "reserved for a coaching session",
  );
  await closeAll(su, c);
});

Deno.test("session: a scheduled maintenance block blocks the session (§12)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);
  const cat = (
    await su.queryObject<{ id: string }>(
      `select id from maintenance_issue_categories where facility_id is null limit 1`,
    )
  ).rows[0].id;
  await c.queryArray({
    text:
      `select create_maintenance_ticket($1,$2,$3,'HIGH','Nets','x', $4, $5)`,
    args: [facilityId, courtId, cat, ist(16), ist(19)],
  });
  await assertRejects(
    () => session(c, facilityId, p, coachId, courtId, 17, 18),
    Error,
    "maintenance",
  );
  await closeAll(su, c);
});

Deno.test("session: coach outside their availability window is rejected (§11 availability)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = (
    await c.queryObject<{ id: string }>({
      text: `select (add_coach($1,$2)).id as id`,
      args: [facilityId, u],
    })
  ).rows[0].id;
  // availability only 06:00-08:00 every day
  await c.queryArray({
    text: `select set_coach_availability($1, $2::jsonb)`,
    args: [
      coachId,
      JSON.stringify(
        [0, 1, 2, 3, 4, 5, 6].map((d) => ({
          dayOfWeek: d,
          startTime: "06:00",
          endTime: "08:00",
        })),
      ),
    ],
  });
  const p = await program(c, facilityId);
  await assertRejects(
    () => session(c, facilityId, p, coachId, courtId, 17, 18),
    Error,
    "coach is not available",
  );
  await closeAll(su, c);
});

Deno.test("session: complete records completion and keeps a cancelled row intact", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);
  const s1 = await session(c, facilityId, p, coachId, courtId, 9, 10);
  await c.queryArray({
    text: `select complete_coaching_session($1, 'Good session', null)`,
    args: [s1],
  });
  const done = await su.queryObject<
    { status: string; completed_at: string | null }
  >({
    text: `select status, completed_at from coaching_sessions where id=$1`,
    args: [s1],
  });
  assertEquals(done.rows[0].status, "COMPLETED");
  assert(done.rows[0].completed_at);

  const s2 = await session(c, facilityId, p, coachId, courtId, 11, 12);
  await c.queryArray({
    text: `select cancel_coaching_session($1, 'Coach unwell')`,
    args: [s2],
  });
  const cancelled = await su.queryObject<
    { status: string; cancel_reason: string; start_at: string }
  >({
    text:
      `select status, cancel_reason, start_at from coaching_sessions where id=$1`,
    args: [s2],
  });
  assertEquals(cancelled.rows[0].status, "CANCELLED");
  assertEquals(cancelled.rows[0].cancel_reason, "Coach unwell");
  assert(
    cancelled.rows[0].start_at,
    "the original schedule is preserved (§53)",
  );
  // A cancelled session frees the court.
  await session(c, facilityId, p, coachId, courtId, 11, 12);
  await closeAll(su, c);
});

// ── Enrollments & capacity (§15 / §20 / §52) ────────────────────────────────
Deno.test("enrollment: one active enrollment per member per program", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const m = await makeMember(su, facilityId);
  const p = await program(c, facilityId);
  await enrollment(c, facilityId, m, p);
  await assertRejects(
    () =>
      c.queryArray({
        text: `select create_coaching_enrollment($1,$2,$3)`,
        args: [facilityId, m, p],
      }),
    Error,
    "already has an active enrollment",
  );
  await closeAll(su, c);
});

Deno.test("session roster: cannot exceed capacity", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId, { capacity: 2 });
  const s = await session(c, facilityId, p, coachId, courtId, 9, 10, 2);

  const e1 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "A"),
    p,
  );
  const e2 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "B"),
    p,
  );
  const e3 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "C"),
    p,
  );
  await c.queryArray({
    text: `select add_session_student($1,$2)`,
    args: [s, e1],
  });
  await c.queryArray({
    text: `select add_session_student($1,$2)`,
    args: [s, e2],
  });
  await assertRejects(
    () =>
      c.queryArray({
        text: `select add_session_student($1,$2)`,
        args: [s, e3],
      }),
    Error,
    "full",
  );
  await closeAll(su, c);
});

Deno.test("session roster: two concurrent adds to the last seat — exactly one succeeds (§52)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId, { capacity: 2 });
  const s = await session(c, facilityId, p, coachId, courtId, 9, 10, 2);
  const e1 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "A"),
    p,
  );
  await c.queryArray({
    text: `select add_session_student($1,$2)`,
    args: [s, e1],
  });
  const e2 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "B"),
    p,
  );
  const e3 = await enrollment(
    c,
    facilityId,
    await makeMember(su, facilityId, "C"),
    p,
  );

  const a = await authed(owner);
  const b = await authed(owner);
  const add = (cl: C, e: string) =>
    cl.queryArray({ text: `select add_session_student($1,$2)`, args: [s, e] });
  const res = await Promise.allSettled([add(a, e2), add(b, e3)]);
  const wins = res.filter((r) => r.status === "fulfilled").length;
  assertEquals(
    wins,
    1,
    "only one of the two racing adds may take the last seat",
  );

  const n = await su.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from coaching_session_students where session_id=$1 and status='ENROLLED'`,
    args: [s],
  });
  assertEquals(Number(n.rows[0].n), 2);
  await closeAll(su, c, a, b);
});

// ── Court + coach concurrency (§50 / §51) ───────────────────────────────────
Deno.test("court concurrency: create_booking vs create_coaching_session for one slot — exactly one wins (§50)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);

  const a = await authed(owner);
  const b = await authed(owner);
  const book = () =>
    a.queryArray({
      text:
        `select create_booking($1,$2,$3,$4,'GUEST',null,'Racer',null,null,'PENDING',null,1,null)`,
      args: [facilityId, courtId, ist(16), ist(17)],
    });
  const sess = () =>
    b.queryArray({
      text:
        `select create_coaching_session($1,$2,$3,$4,$5,$6,null,null,null,'SCHEDULED',false)`,
      args: [facilityId, p, coachId, courtId, ist(16), ist(17)],
    });

  const res = await Promise.allSettled([book(), sess()]);
  const wins = res.filter((r) => r.status === "fulfilled").length;
  assertEquals(
    wins,
    1,
    "the advisory lock + predicate must let exactly one through",
  );

  const bn = await su.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from bookings where court_id=$1 and status in ('pending','confirmed')`,
    args: [courtId],
  });
  const sn = await su.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from coaching_sessions where court_id=$1 and status in ('SCHEDULED','CONFIRMED','IN_PROGRESS')`,
    args: [courtId],
  });
  assertEquals(Number(bn.rows[0].n) + Number(sn.rows[0].n), 1);
  await closeAll(su, c, a, b);
});

Deno.test("coach concurrency: two create_coaching_session for one coach/slot — exactly one wins (§51)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const { courtId: court2 } = await makeOpenCourt(su, facilityId);
  const p = await program(c, facilityId);

  const a = await authed(owner);
  const b = await authed(owner);
  const mk = (cl: C, court: string) =>
    cl.queryArray({
      text:
        `select create_coaching_session($1,$2,$3,$4,$5,$6,null,null,null,'SCHEDULED',false)`,
      args: [facilityId, p, coachId, court, ist(16), ist(17)],
    });
  const res = await Promise.allSettled([mk(a, courtId), mk(b, court2)]);
  assertEquals(res.filter((r) => r.status === "fulfilled").length, 1);
  const n = await su.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from coaching_sessions where coach_id=$1 and status<>'CANCELLED'`,
    args: [coachId],
  });
  assertEquals(Number(n.rows[0].n), 1);
  await closeAll(su, c, a, b);
});

// ── Finance (§26 / §28 / §71) ──────────────────────────────────────────────
Deno.test("finance: an unpaid enrollment is an obligation, not revenue; recording payment recognises it", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const m = await makeMember(su, facilityId);
  const p = await program(c, facilityId, { price: 300000 });
  const e = await enrollment(c, facilityId, m, p);

  // Appears as outstanding in Pending Payments.
  const pending = await c.queryObject<
    { source_type: string; outstanding_minor: bigint }
  >({
    text:
      `select source_type, outstanding_minor from list_pending_payments($1, null, 'COACHING_ENROLLMENT') where source_id = $2`,
    args: [facilityId, e],
  });
  assertEquals(pending.rows[0].source_type, "COACHING_ENROLLMENT");
  assertEquals(Number(pending.rows[0].outstanding_minor), 300000);

  // Not yet collected revenue.
  const before = await c.queryObject<{ gross: bigint; outstanding: bigint }>({
    text:
      `select gross_revenue_minor gross, outstanding_minor outstanding from get_finance_summary($1, 'THIS_YEAR')`,
    args: [facilityId],
  });
  assertEquals(Number(before.rows[0].gross), 0);
  assert(Number(before.rows[0].outstanding) >= 300000);

  await c.queryArray({
    text:
      `select record_obligation_payment('COACHING_ENROLLMENT', $1, 300000, 'UPI')`,
    args: [e],
  });

  const after = await c.queryObject<{ gross: bigint }>({
    text:
      `select gross_revenue_minor gross from get_finance_summary($1, 'THIS_YEAR')`,
    args: [facilityId],
  });
  assertEquals(Number(after.rows[0].gross), 300000);

  // Classified as coaching in the revenue breakdown (0087).
  const bd = await c.queryObject<{ coaching: bigint; member_booking: bigint }>({
    text:
      `select coaching_revenue_minor coaching, member_booking_revenue_minor member_booking from get_revenue_breakdown($1, 'THIS_YEAR')`,
    args: [facilityId],
  });
  assertEquals(Number(bd.rows[0].coaching), 300000);
  assertEquals(Number(bd.rows[0].member_booking), 0);

  const gone = await c.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from list_pending_payments($1, null, 'COACHING_ENROLLMENT', 'ALL_OUTSTANDING') where source_id=$2`,
    args: [facilityId, e],
  });
  assertEquals(Number(gone.rows[0].n), 0);
  await closeAll(su, c);
});

Deno.test("membership: a membership-included program enrolment is ₹0 — no obligation, no revenue (§27 / §72)", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const m = await makeMember(su, facilityId);
  const p = await program(c, facilityId, { price: null, included: true });
  const e = await enrollment(c, facilityId, m, p);

  const row = await su.queryObject<
    { price_minor: number; pricing_type: string }
  >({
    text:
      `select price_minor, pricing_type from coaching_enrollments where id=$1`,
    args: [e],
  });
  assertEquals(row.rows[0].price_minor, 0);
  assertEquals(row.rows[0].pricing_type, "MEMBERSHIP_INCLUDED");

  const pending = await c.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from list_pending_payments($1) where source_id=$2`,
    args: [facilityId, e],
  });
  assertEquals(
    Number(pending.rows[0].n),
    0,
    "a ₹0 enrolment never appears as owed",
  );

  await assertRejects(
    () =>
      c.queryArray({
        text:
          `select record_obligation_payment('COACHING_ENROLLMENT', $1, 1000, 'Cash')`,
        args: [e],
      }),
    Error,
    "nothing to collect",
  );
  await closeAll(su, c);
});

// ── RLS / facility isolation (§76) ─────────────────────────────────────────
Deno.test("RLS: a facility-B user cannot read facility-A coaching data", async () => {
  const su = await superuser();
  const { owner: ownerA, facilityId: fA, courtId } = await seed(su);
  const cA = await authed(ownerA);
  const uA = await makeUser(su);
  await addStaff(su, fA, uA, "staff");
  const coachId = await coach(cA, fA, uA);
  const pA = await program(cA, fA);
  const mA = await makeMember(su, fA);
  const eA = await enrollment(cA, fA, mA, pA);
  const sA = await session(cA, fA, pA, coachId, courtId, 9, 10);
  await cA.queryArray({
    text:
      `select add_progress_note($1, 'Backhand improving', 'Backhand', 'ON_TRACK', null)`,
    args: [eA],
  });

  const ownerB = await makeUser(su);
  await makeFacility(su, ownerB);
  const cB = await authed(ownerB);

  for (
    const [table, id] of [
      ["coaches", coachId],
      ["coaching_programs", pA],
      ["coaching_sessions", sA],
      ["coaching_enrollments", eA],
    ] as const
  ) {
    const r = await cB.queryObject<{ n: bigint }>({
      text: `select count(*)::bigint n from ${table} where id = $1`,
      args: [id],
    });
    assertEquals(Number(r.rows[0].n), 0, `facility B must not see ${table}`);
  }
  const notes = await cB.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from student_progress_notes where enrollment_id = $1`,
    args: [eA],
  });
  assertEquals(
    Number(notes.rows[0].n),
    0,
    "facility B must not see progress notes",
  );

  // …and the RPCs refuse outright.
  await assertRejects(
    () =>
      cB.queryArray({ text: `select get_coaching_overview($1)`, args: [fA] }),
    Error,
    "permission",
  );
  await assertRejects(
    () => cB.queryArray({ text: `select get_coach($1)`, args: [coachId] }),
    Error,
    "permission",
  );
  await closeAll(su, cA, cB);
});

// ── Permission gates (§36 / §37 / §77) ─────────────────────────────────────
Deno.test("permissions: a view-only user cannot manage coaches, programs or sessions", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);

  const viewer = await userWithPerms(su, facilityId, ["COACHING_VIEW"]);
  const vc = await authed(viewer);
  const anotherStaff = await makeUser(su);

  await assertRejects(
    () =>
      vc.queryArray({
        text: `select create_coaching_program($1, 'X')`,
        args: [facilityId],
      }),
    Error,
    "permission",
  );
  await assertRejects(
    () =>
      vc.queryArray({
        text: `select add_coach($1, $2)`,
        args: [facilityId, anotherStaff],
      }),
    Error,
    "permission",
  );
  await assertRejects(
    () =>
      vc.queryArray({
        text: `select create_coaching_session($1,$2,$3,$4,$5,$6)`,
        args: [facilityId, p, coachId, courtId, ist(9), ist(10)],
      }),
    Error,
    "permission",
  );
  await closeAll(su, c, vc);
});

Deno.test("permissions: a coach-style role can run a session + note progress, but not cancel or manage programs (§37)", async () => {
  const su = await superuser();
  const { owner, facilityId, courtId } = await seed(su);
  const c = await authed(owner);
  const u = await makeUser(su);
  await addStaff(su, facilityId, u, "staff");
  const coachId = await coach(c, facilityId, u);
  const p = await program(c, facilityId);
  const m = await makeMember(su, facilityId);
  const e = await enrollment(c, facilityId, m, p);
  const s = await session(c, facilityId, p, coachId, courtId, 9, 10);

  const coachUser = await userWithPerms(su, facilityId, [
    "COACHING_VIEW",
    "COACHING_EDIT_SESSION",
    "COACHING_VIEW_PROGRESS",
    "COACHING_MANAGE_PROGRESS",
  ]);
  const cc = await authed(coachUser);

  await cc.queryArray({
    text: `select complete_coaching_session($1, 'ran it', null)`,
    args: [s],
  });
  await cc.queryArray({
    text:
      `select add_progress_note($1, 'Serve is better', null, 'ON_TRACK', null)`,
    args: [e],
  });

  const s2 = await session(c, facilityId, p, coachId, courtId, 11, 12);
  await assertRejects(
    () =>
      cc.queryArray({
        text: `select cancel_coaching_session($1, 'nope')`,
        args: [s2],
      }),
    Error,
    "permission",
  );
  await assertRejects(
    () =>
      cc.queryArray({
        text: `select create_coaching_program($1, 'Y')`,
        args: [facilityId],
      }),
    Error,
    "permission",
  );
  await closeAll(su, c, cc);
});

Deno.test("progress: an unauthorized user cannot add a note or read notes", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const m = await makeMember(su, facilityId);
  const p = await program(c, facilityId);
  const e = await enrollment(c, facilityId, m, p);
  await c.queryArray({
    text:
      `select add_progress_note($1, 'Note by owner', null, 'ON_TRACK', null)`,
    args: [e],
  });

  const viewer = await userWithPerms(su, facilityId, ["COACHING_VIEW"]); // no VIEW_PROGRESS / MANAGE_PROGRESS
  const vc = await authed(viewer);
  await assertRejects(
    () =>
      vc.queryArray({
        text: `select add_progress_note($1, 'sneaky', null, 'ON_TRACK', null)`,
        args: [e],
      }),
    Error,
    "permission",
  );
  const seen = await vc.queryObject<{ n: bigint }>({
    text:
      `select count(*)::bigint n from student_progress_notes where enrollment_id = $1`,
    args: [e],
  });
  assertEquals(
    Number(seen.rows[0].n),
    0,
    "COACHING_VIEW alone must not expose progress notes (§34)",
  );
  await closeAll(su, c, vc);
});
