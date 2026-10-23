// Generates supabase/migrations/0156_page_access_enforcement.sql.
//
// For every data function in the GUARDS table below it takes the function's CURRENT definition from the migrations and
// re-creates it with one extra line at the top of its body: a check that the caller's role grants the page (View for
// reads, Edit for writes). It also adds the coach "own data only" filters to the coaching reads.
//
//   node scripts/gen-access-enforcement.cjs
//
// Functions written in plain SQL (not PL/pgSQL) can't carry a guard line; they are listed in the report at the end and
// are covered by the view-level checks on the functions they call / the table policies.
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const MIG = path.join(ROOT, "supabase/migrations");

// ── 1. read the latest definition of every function ───────────────────────────
const files = fs.readdirSync(MIG).filter((f) => f.endsWith(".sql") && f < "0156").sort();
const FN_RE = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_0-9]+)\s*\(([\s\S]*?)\)\s*returns\s+([\s\S]*?)\s+(?:language\s+(\w+))[\s\S]*?(\$[a-z_]*\$)([\s\S]*?)\5\s*;?/gi;
const defs = new Map();
for (const f of files) {
  const s = fs.readFileSync(path.join(MIG, f), "utf8").replace(/\r\n/g, "\n");
  let m;
  FN_RE.lastIndex = 0;
  while ((m = FN_RE.exec(s))) {
    defs.set(m[1].toLowerCase(), { file: f, args: m[2], ret: m[3], lang: (m[4] || "").toLowerCase(), tag: m[5], full: m[0], body: m[6] });
  }
}

// ── 2. what to guard ─────────────────────────────────────────────────────────
// facility: "arg"  → the function has p_facility_id / p_facility / target_facility
//           [table, param] → derive the facility from an entity id: (select facility_id from <table> where id = <param>)
// any: the caller needs at least one of these permission keys
const arg = "arg";
const G = [];
const g = (names, facility, any, extra = {}) => names.split(/\s+/).filter(Boolean).forEach((name) => G.push({ name, facility, any, ...extra }));

// Reports & analytics. Several are shared with Home and the finance / membership dashboards, so any page that uses
// them may call them.
g("get_reports_overview get_reports_overview_trend get_analytics_overview", arg, ["REPORT_OVERVIEW_VIEW", "DASHBOARD_VIEW"]);
g("get_booking_analytics get_booking_source_split get_booking_trend get_bookings_by_sport get_demand_heatmap get_peak_hours", arg, ["REPORT_OVERVIEW_VIEW", "REPORT_UTILIZATION_VIEW", "DASHBOARD_VIEW"]);
g("get_court_utilization get_overall_utilization get_sport_utilization", arg, ["REPORT_UTILIZATION_VIEW", "REPORT_OVERVIEW_VIEW", "DASHBOARD_VIEW"]);
g("get_revenue_breakdown get_revenue_by_court get_revenue_by_sport get_revenue_trend get_payment_method_breakdown", arg, ["REPORT_REVENUE_VIEW", "REPORT_OVERVIEW_VIEW", "FINANCE_VIEW", "DASHBOARD_VIEW"]);
g("get_finance_summary", arg, ["FINANCE_VIEW", "REPORT_REVENUE_VIEW", "DASHBOARD_VIEW"]);
g("get_membership_analytics get_memberships_by_type get_membership_session_analytics get_membership_member_counts get_membership_batch_breakdown", arg, ["REPORT_MEMBERSHIPS_VIEW", "MEMBERSHIPS_VIEW", "MEMBERSHIP_SESSIONS_VIEW", "REPORT_OVERVIEW_VIEW", "DASHBOARD_VIEW"]);
g("get_guest_booking_analytics get_guest_bookings_by_court get_guest_bookings_by_sport get_guest_peak_hours get_guest_release_analytics", arg, ["REPORT_GUESTS_VIEW", "GUEST_BOOKINGS_VIEW", "REPORT_OVERVIEW_VIEW", "DASHBOARD_VIEW"]);

// Finance
g("list_finance_transactions count_finance_transactions list_finance_ledger list_finance_payment_methods", arg, ["FINANCE_TRANSACTIONS_VIEW", "FINANCE_VIEW"]);
g("list_pending_payments get_pending_payments_summary", arg, ["FINANCE_PAYMENTS_VIEW", "FINANCE_VIEW", "DASHBOARD_VIEW"]);
g("list_expenses", arg, ["FINANCE_EXPENSES_VIEW", "FINANCE_VIEW"]);
g("list_daily_closings get_daily_closing_summary", arg, ["FINANCE_CLOSING_VIEW"]);
g("list_refunds list_settlement_exceptions", arg, ["REFUNDS_VIEW", "FINANCE_VIEW"]);
g("get_finance_transaction get_transaction_details", ["finance_transactions_view", "p_transaction_id"], ["FINANCE_TRANSACTIONS_VIEW", "FINANCE_VIEW"]);
g("initiate_manual_refund request_refund", ["payment_orders", "p_payment_order_id"], ["FINANCE_REFUND"]);

// Maintenance
g("get_maintenance_overview get_maintenance_court_status list_maintenance_tickets", arg, ["MAINTENANCE_VIEW"]);
g("list_maintenance_issue_categories", arg, ["MAINTENANCE_CATEGORIES_VIEW", "MAINTENANCE_VIEW"]);
g("create_maintenance_ticket", arg, ["MAINTENANCE_CREATE"]);
g("create_maintenance_issue_category", arg, ["MAINTENANCE_CATEGORIES_EDIT"]);
g("update_maintenance_issue_category", ["maintenance_issue_categories", "p_category_id"], ["MAINTENANCE_CATEGORIES_EDIT"]);
g("get_maintenance_ticket_detail", ["maintenance_tickets", "p_ticket_id"], ["MAINTENANCE_VIEW"]);
g("add_maintenance_note add_maintenance_attachment update_maintenance_ticket close_maintenance_ticket reopen_maintenance_ticket", ["maintenance_tickets", "p_ticket_id"], ["MAINTENANCE_CREATE", "MAINTENANCE_RESOLVE"]);
g("assign_maintenance_ticket", ["maintenance_tickets", "p_ticket_id"], ["MAINTENANCE_ASSIGN"]);
g("schedule_maintenance", ["maintenance_tickets", "p_ticket_id"], ["MAINTENANCE_SCHEDULE"]);
g("start_maintenance_ticket resolve_maintenance_ticket update_maintenance_cost", ["maintenance_tickets", "p_ticket_id"], ["MAINTENANCE_RESOLVE"]);

// Memberships
g("list_memberships get_membership_page_summary get_membership_revenue_timeseries get_member_stats list_assignable_batches", arg, ["MEMBERSHIPS_VIEW", "MEMBERSHIP_SESSIONS_VIEW", "DASHBOARD_VIEW"]);
g("search_facility_members search_members", arg, ["MEMBERSHIPS_VIEW", "BOOKINGS_VIEW", "BOOKINGS_CREATE", "GUEST_BOOKINGS_CREATE", "MEMBERSHIP_SESSIONS_VIEW", "COACHING_STUDENTS_VIEW", "COACHING_MANAGE_ENROLLMENTS"]);
g("list_member_schedules", arg, ["MEMBERSHIP_SCHEDULE_VIEW"]);
g("list_membership_sessions_admin get_membership_sessions_summary get_membership_utilization_sessions", arg, ["MEMBERSHIP_SESSIONS_VIEW"]);
g("list_membership_sessions_for_date", arg, ["MEMBERSHIP_SESSIONS_VIEW", "BOOKINGS_VIEW", "MEMBERSHIPS_VIEW"]);
g("create_member create_membership create_membership_full", arg, ["MEMBERSHIPS_CREATE"]);
g("set_facility_membership_access_days", arg, ["MEMBERSHIPS_EDIT", "MEMBERSHIP_PLANS_EDIT"]);
g("create_membership_batch", arg, ["MEMBERSHIP_SESSIONS_EDIT", "MEMBERSHIP_PLANS_EDIT"]);
g("update_member", ["members", "p_member_id"], ["MEMBERSHIPS_EDIT"]);
g("delete_member", ["members", "p_member_id"], ["MEMBERSHIPS_CANCEL", "MEMBERSHIPS_EDIT"]);
g("get_membership_detail", ["memberships", "p_membership_id"], ["MEMBERSHIPS_VIEW"]);
g("update_membership_full", ["memberships", "p_membership_id"], ["MEMBERSHIPS_EDIT"]);
g("cancel_membership", ["memberships", "p_membership_id"], ["MEMBERSHIPS_CANCEL"]);
g("record_membership_payment", ["memberships", "p_membership_id"], ["FINANCE_RECORD_PAYMENT", "MEMBERSHIPS_EDIT"]);
g("get_membership_session_detail list_membership_session_activity list_membership_session_bookings list_membership_session_members list_membership_session_occurrences", ["membership_batches", "p_batch_id"], ["MEMBERSHIP_SESSIONS_VIEW"]);
g("assign_batch_member remove_batch_member block_membership_batch_date unblock_membership_batch_date duplicate_membership_batch update_membership_batch set_membership_batch_notes book_guest_slot book_membership_slot", ["membership_batches", "p_batch_id"], ["MEMBERSHIP_SESSIONS_EDIT"]);

// Guests & bookings
g("list_guest_bookings_admin get_guest_bookings_summary", arg, ["GUEST_BOOKINGS_VIEW"]);
g("find_or_create_guest", arg, ["GUEST_BOOKINGS_CREATE", "BOOKINGS_CREATE", "GUEST_PLAYERS_EDIT"]);
g("get_guest_stats", ["guest_players", "p_guest_id"], ["GUEST_PLAYERS_VIEW", "GUEST_BOOKINGS_VIEW"]);
g("update_guest", ["guest_players", "p_guest_id"], ["GUEST_PLAYERS_EDIT"]);
g("create_booking", arg, ["BOOKINGS_CREATE", "GUEST_BOOKINGS_CREATE", "COACHING_CREATE_SESSION", "COACHING_EDIT_SESSION", "MEMBERSHIPS_CREATE", "MEMBERSHIP_SESSIONS_EDIT"]);
g("reschedule_booking", ["bookings", "p_booking_id"], ["BOOKINGS_EDIT", "GUEST_BOOKINGS_EDIT", "COACHING_EDIT_SESSION", "COACHING_CREATE_SESSION"]);
g("cancel_booking", ["bookings", "p_booking_id"], ["BOOKINGS_CANCEL", "GUEST_BOOKINGS_CANCEL", "COACHING_CANCEL_SESSION", "MEMBERSHIPS_CANCEL"]);
g("complete_guest_booking duplicate_guest_booking update_guest_booking", ["bookings", "p_booking_id"], ["GUEST_BOOKINGS_EDIT", "BOOKINGS_EDIT"]);
g("delete_guest_booking", ["bookings", "p_booking_id"], ["GUEST_BOOKINGS_CANCEL", "BOOKINGS_CANCEL"]);
g("record_guest_booking_payment", ["bookings", "p_booking_id"], ["BOOKINGS_MANAGE_PAYMENTS", "FINANCE_RECORD_PAYMENT", "GUEST_BOOKINGS_EDIT"]);

// Facility settings
g("upsert_cancellation_policy", arg, ["FACILITY_SETTINGS_EDIT"]);

// Coaching — page-level view guards on top of the existing COACHING_VIEW checks
g("get_coaching_overview get_coaching_card_stats get_coaching_insights get_coaching_total_revenue", arg, ["COACHING_VIEW"], { denyScoped: true });
g("list_coaching_programs get_program_card_stats get_program_insights", arg, ["COACHING_PROGRAMS_VIEW"]);
g("get_coaching_program", ["coaching_programs", "p_program_id"], ["COACHING_PROGRAMS_VIEW", "COACHING_SESSIONS_VIEW", "COACHING_STUDENTS_VIEW"]);
g("list_coaching_program_options", arg, ["COACHING_PROGRAMS_VIEW", "COACHING_SESSIONS_VIEW", "COACHING_STUDENTS_VIEW", "COACHING_CREATE_SESSION"]);
g("list_coaching_enrollments get_student_card_stats", arg, ["COACHING_STUDENTS_VIEW"]);
g("get_coaching_enrollment", ["coaching_enrollments", "p_enrollment_id"], ["COACHING_STUDENTS_VIEW"]);
g("list_coaching_sessions", arg, ["COACHING_SESSIONS_VIEW", "COACHING_SCHEDULE_VIEW"]);
g("get_coaching_session", ["coaching_sessions", "p_session_id"], ["COACHING_SESSIONS_VIEW", "COACHING_SCHEDULE_VIEW"]);
g("list_coaching_events", arg, ["COACHING_SESSIONS_VIEW", "COACHING_SCHEDULE_VIEW", "COACHING_VIEW"]);
g("get_coaching_reports", arg, ["COACHING_REPORTS_VIEW"], { denyScoped: true });
g("get_coach", ["coaches", "p_coach_id"], ["COACHING_VIEW"], { ownCoachById: "p_coach_id" });

// ── 3. coach "own data only" filters (string edits on the coaching reads) ────────
const OWN = (fac, col) => `(not coaching_scope_own(${fac}) or ${col} = my_coach_id(${fac}))`;
const EDITS = {
  list_coaches: [["where co.facility_id = p_facility_id and coaching_sport_ok_coach(", `where co.facility_id = p_facility_id and ${OWN("p_facility_id", "co.id")} and coaching_sport_ok_coach(`]],
  list_coach_options: [["where c.facility_id = p_facility_id and c.status = 'ACTIVE'", `where c.facility_id = p_facility_id and ${OWN("p_facility_id", "c.id")} and c.status = 'ACTIVE'`]],
  list_coaching_sessions: [["where cs.facility_id = p_facility_id and coaching_sport_ok_court(", `where cs.facility_id = p_facility_id and ${OWN("p_facility_id", "cs.coach_id")} and coaching_sport_ok_court(`]],
  list_coaching_enrollments: [["where e.facility_id = p_facility_id and coaching_sport_ok_program(", `where e.facility_id = p_facility_id and ${OWN("p_facility_id", "e.coach_id")} and coaching_sport_ok_program(`]],
  list_coaching_programs: [[
    "where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or",
    "where cp.facility_id = p_facility_id and (not coaching_scope_own(p_facility_id) or exists (select 1 from coaching_sessions own_s where own_s.program_id = cp.id and own_s.coach_id = my_coach_id(p_facility_id)) or exists (select 1 from coaching_enrollments own_e where own_e.program_id = cp.id and own_e.coach_id = my_coach_id(p_facility_id))) and (p_facility_sport_ids is null or",
  ]],
};

// ── 4. build ───────────────────────────────────────────────────────────────────
const report = { done: [], wrapped: [], skippedSql: [], missing: [], noArg: [] };
const out = [];
const KEYS = (a) => "array[" + a.map((k) => `'${k}'`).join(", ") + "]";

function facilityExpr(def, spec) {
  if (spec === arg) {
    const m = /\b(p_facility_id|p_facility|target_facility)\b/.exec(def.args);
    return m ? m[1] : null;
  }
  const [table, param] = spec;
  if (!new RegExp("\\b" + param + "\\b").test(def.args)) return null;
  return `(select t.facility_id from ${table} t where t.id = ${param})`;
}

/** Splits a parameter list on top-level commas. */
function splitArgs(args) {
  const parts = [];
  let depth = 0, cur = "";
  for (const ch of args) {
    if (ch === "(" || ch === "[") depth++;
    if (ch === ")" || ch === "]") depth--;
    if (ch === "," && depth === 0) { parts.push(cur); cur = ""; } else cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  return parts.map((p) => p.replace(/--[^\n]*/g, "").trim()).filter(Boolean);
}

/**
 * A plain-SQL function can't carry a guard line, so it becomes a private implementation (_<name>_impl, callable by no one
 * but the owner) behind a SECURITY DEFINER PL/pgSQL wrapper of the same name and signature that checks access first.
 */
function wrapSqlFunction(item, def, fexpr) {
  const name = item.name;
  const impl = "_" + name + "_impl";
  const params = splitArgs(def.args).map((p) => {
    const m = /^(\w+)\s+([\s\S]*?)(?:\s+default\s+[\s\S]*|\s*=\s*[\s\S]*)?$/i.exec(p);
    return { raw: p, name: m[1], type: m[2].trim() };
  });
  const implText = def.full.replace(/^create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?[a-z_0-9]+/i, "create or replace function " + impl);
  const stable = /\bstable\b/i.test(def.full.slice(0, def.full.search(/\$[a-z_]*\$/))) ? "stable " : "";
  const retText = def.ret.trim();
  const isSet = /^(table|setof)\b/i.test(retText);
  const isVoid = /^void$/i.test(retText);
  const call = impl + "(" + params.map((p) => p.name + " => " + p.name).join(", ") + ")";
  const inner = isVoid ? "perform " + call + ";" : isSet ? "return query select * from " + call + ";" : "return " + call + ";";
  const sig = params.map((p) => p.type).join(", ");
  return [
    "-- " + name + " (was " + def.file + ", plain SQL — now guarded through a private implementation)",
    implText.trimEnd().replace(/;?$/, ";"),
    "revoke all on function " + impl + "(" + sig + ") from public, anon, authenticated;",
    "create or replace function " + name + "(" + params.map((p) => p.raw).join(", ") + ")",
    "returns " + retText + " language plpgsql " + stable + "security definer set search_path = public as $w$",
    "begin",
    "  perform require_page_access_any(" + fexpr + ", " + KEYS(item.any) + ");",
    "  " + inner,
    "end;",
    "$w$;",
    "",
  ].join("\n");
}

for (const item of G) {
  const def = defs.get(item.name);
  if (!def) { report.missing.push(item.name); continue; }
  const fexpr = facilityExpr(def, item.facility);
  if (!fexpr) { report.noArg.push(item.name); continue; }
  if (def.lang === "sql") {
    out.push(wrapSqlFunction(item, def, fexpr));
    report.wrapped.push(item.name);
    continue;
  }
  if (def.lang !== "plpgsql") { report.skippedSql.push(item.name); continue; }

  let lines = [`  perform require_page_access_any(${fexpr}, ${KEYS(item.any)});`];
  if (item.denyScoped) lines.push(`  if coaching_scope_own(${fexpr}) then raise exception 'This is not available for your role.' using errcode = '42501'; end if;`);
  if (item.ownCoachById) lines.push(`  if coaching_scope_own(${fexpr}) and ${item.ownCoachById} is distinct from my_coach_id(${fexpr}) then raise exception 'You can only view your own coach profile.' using errcode = '42501'; end if;`);
  const guard = lines.join("\n") + "\n";

  // insert after the first top-level `begin`
  const body = def.body;
  let at = -1;
  const re = /(^|\n)([ \t]*)begin\b[^\n]*\n/gi;
  let m;
  while ((m = re.exec(body))) {
    const before = body.slice(0, m.index);
    if (/--[^\n]*$/.test(before.split("\n").pop())) continue;
    at = m.index + m[0].length;
    break;
  }
  if (at < 0) { report.noArg.push(item.name + " (no begin)"); continue; }
  let newBody = body.slice(0, at) + guard + body.slice(at);
  for (const [from, to] of EDITS[item.name] || []) {
    if (!newBody.includes(from)) throw new Error("coach-scope anchor missing in " + item.name + ": " + from.slice(0, 50));
    newBody = newBody.replace(from, to);
  }
  const text = def.full.replace(body, () => newBody).replace(/^create\s+function/i, "create or replace function");
  out.push(`-- ${item.name} (was ${def.file})\n${text.trimEnd().replace(/;?$/, ";")}\n`);
  report.done.push(item.name);
}

// Coaching reads that carry only the scope filter (they are already guarded by COACHING_VIEW).
for (const name of ["list_coaches", "list_coach_options"]) {
  if (G.some((x) => x.name === name)) continue;
  const def = defs.get(name);
  if (!def || def.lang !== "plpgsql") continue;
  let text = def.full.replace(/^create\s+function/i, "create or replace function");
  for (const [from, to] of EDITS[name]) {
    if (!text.includes(from)) throw new Error("anchor missing in " + name);
    text = text.replace(from, to);
  }
  out.push(`-- ${name} (was ${def.file}) — own-coach filter\n${text.trimEnd().replace(/;?$/, ";")}\n`);
  report.done.push(name);
}

const header = `-- Page access enforcement in the database.
--
-- The role editor's None / View / Edit matrix (migration 0155) is enforced here, so a role can't read or change what its
-- pages don't grant by calling the API directly. Each data function below is re-created with one extra line at the top of
-- its body: require_page_access_any(<facility>, <keys>), which raises 42501 unless the caller holds at least one key.
-- Service-role callers (edge functions, webhooks: no end user) are exempt. Owners hold every key.
--
-- It also adds the coach scope: for a non-owner whose role carries COACHING_OWN_ONLY the coaching reads return only
-- their own coach profile, sessions, programs and students, and the facility-wide coaching stats / reports are refused.
--
-- GENERATED by scripts/gen-access-enforcement.cjs from the current function definitions — re-run it rather than editing.

create or replace function require_page_access_any(p_facility uuid, p_permissions text[])
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is null or p_facility is null then
    return; -- service role / internal call, or an id that doesn't exist (the function reports that itself)
  end if;
  if exists (select 1 from unnest(p_permissions) k where has_permission(p_facility, k)) then
    return;
  end if;
  raise exception 'You don''t have access to this page.' using errcode = '42501';
end;
$$;
grant execute on function require_page_access_any(uuid, text[]) to authenticated;

`;
fs.writeFileSync(path.join(MIG, "0156_page_access_enforcement.sql"), header + out.join("\n"));
console.log("guarded:", report.done.length, "wrapped SQL:", report.wrapped.length, "\nskipped (SQL-language):", report.skippedSql.join(", "), "\nmissing:", report.missing.join(", "), "\nno facility arg/begin:", report.noArg.join(", "));
