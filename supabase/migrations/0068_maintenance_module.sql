-- ═══════════════════════════════════════════════════════════════════════════
-- Maintenance & Court Operations — a new source that participates in the
-- existing architecture, not a parallel one.
--
--   maintenance_issue_categories — reused shape from expense_categories
--   (0046): facility_id null = shared default, a facility's own rows are
--   private to it.
--
--   maintenance_tickets — the record. facility_sport_id is denormalized from
--   the court exactly like bookings.facility_sport_id (0007). Status is
--   forward-driven by the RPCs below, never written directly by a client.
--
--   maintenance_blocks — the ONLY new thing that touches availability. One
--   row per scheduled/active maintenance window, with the same GiST
--   exclusion-constraint concurrency guarantee bookings_no_overlap already
--   gives bookings (0001). court_has_active_maintenance_block() is then
--   wired into the SAME functions availability already goes through —
--   create_booking, reschedule_booking, get_public_court_availability — the
--   same way court_has_active_membership_window (0014/0045) already is.
--   No MaintenanceAvailabilityService, no second engine.
--
--   maintenance_ticket_activity — the audit trail. No generic audit system
--   exists elsewhere in this schema to extend, so this is scoped to the
--   ticket it belongs to, same shape as every other facility-scoped table.
--
--   maintenance_ticket_attachments — metadata only; the bytes live in a new
--   'maintenance-attachments' Storage bucket, object path
--   '<facility_id>/<ticket_id>/<uuid>-<filename>', RLS'd by that first path
--   segment. No prior Storage usage exists in this project to reuse, so this
--   is the minimal facility-scoped pattern, not a bespoke file system.
--
-- Money: actual repair cost posts through the EXISTING create_expense (0046)
-- — Maintenance never inserts into a parallel ledger. Reports read
-- maintenance data straight off these tables/RPCs; no analytics duplication.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- maintenance_issue_categories
-- ─────────────────────────────────────────────────────────────────────────
create table maintenance_issue_categories (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references facilities (id) on delete cascade,
  name text not null,
  icon text not null default 'wrench',
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index maintenance_issue_categories_name_idx
  on maintenance_issue_categories (coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));
create index maintenance_issue_categories_facility_id_idx on maintenance_issue_categories (facility_id);

insert into maintenance_issue_categories (facility_id, name, icon, description, sort_order) values
  (null, 'Net Damaged',        'court',      'Torn or damaged nets',              10),
  (null, 'Lighting Issue',     'lightbulb',  'Lights not working or flickering',  20),
  (null, 'Floor Surface',      'grid',       'Floor damage, wear and tear',       30),
  (null, 'AC/HVAC',            'snowflake',  'Air conditioning and ventilation',  40),
  (null, 'Equipment Fault',    'cog',        'Equipment malfunction or broken',   50),
  (null, 'Water Leakage',      'droplet',    'Water leakage or plumbing issues',  60),
  (null, 'Door/Lock',          'lock',       'Door, lock or access control',      70),
  (null, 'Painting / Interior','paint',      'Walls or interior maintenance',     80),
  (null, 'General Repair',     'wrench',     'General repair work',               90),
  (null, 'Others',             'more',       'Other maintenance issues',          999);

alter table maintenance_issue_categories enable row level security;
create policy "maintenance_categories_select" on maintenance_issue_categories for select
  using (facility_id is null or is_facility_member(facility_id));
create policy "maintenance_categories_write_managers" on maintenance_issue_categories for all
  using (facility_id is not null and has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (facility_id is not null and has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create trigger maintenance_categories_set_updated_at
  before update on maintenance_issue_categories
  for each row execute function set_updated_at();

create function create_maintenance_issue_category(
  p_facility_id uuid, p_name text, p_icon text, p_description text default null, p_sort_order integer default 0
) returns maintenance_issue_categories
language plpgsql
as $$
declare result maintenance_issue_categories;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Category name is required.' using errcode = '23514';
  end if;
  insert into maintenance_issue_categories (facility_id, name, icon, description, sort_order)
  values (p_facility_id, trim(p_name), coalesce(nullif(trim(p_icon), ''), 'wrench'), nullif(trim(coalesce(p_description, '')), ''), coalesce(p_sort_order, 0))
  returning * into result;
  return result;
end;
$$;
grant execute on function create_maintenance_issue_category(uuid, text, text, text, integer) to authenticated;

create function update_maintenance_issue_category(
  p_category_id uuid, p_name text, p_icon text, p_description text default null, p_sort_order integer default 0, p_is_active boolean default true
) returns maintenance_issue_categories
language plpgsql
as $$
declare existing maintenance_issue_categories; result maintenance_issue_categories;
begin
  select * into existing from maintenance_issue_categories where id = p_category_id;
  if existing.id is null then
    raise exception 'Issue category not found' using errcode = 'P0002';
  end if;
  if existing.facility_id is null or not has_facility_role(existing.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Category name is required.' using errcode = '23514';
  end if;
  update maintenance_issue_categories
  set name = trim(p_name),
      icon = coalesce(nullif(trim(p_icon), ''), 'wrench'),
      description = nullif(trim(coalesce(p_description, '')), ''),
      sort_order = coalesce(p_sort_order, 0),
      is_active = coalesce(p_is_active, true),
      updated_at = now()
  where id = p_category_id
  returning * into result;
  return result;
end;
$$;
grant execute on function update_maintenance_issue_category(uuid, text, text, text, integer, boolean) to authenticated;

-- plpgsql (not sql) so the body — which references maintenance_tickets,
-- created further down this migration — is parsed at call time, not now.
create function list_maintenance_issue_categories(p_facility_id uuid, p_include_inactive boolean default true)
returns table (
  id uuid, facility_id uuid, name text, icon text, description text,
  is_active boolean, sort_order integer, issue_count bigint, is_shared boolean
)
language plpgsql
stable
as $$
begin
  return query
  select
    c.id, c.facility_id, c.name, c.icon, c.description, c.is_active, c.sort_order,
    coalesce((select count(*) from maintenance_tickets t where t.issue_category_id = c.id and t.facility_id = p_facility_id), 0)::bigint,
    c.facility_id is null
  from maintenance_issue_categories c
  where (c.facility_id is null or c.facility_id = p_facility_id)
    and (p_include_inactive or c.is_active)
  order by c.sort_order, c.name;
end;
$$;
grant execute on function list_maintenance_issue_categories(uuid, boolean) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- maintenance_tickets
-- ─────────────────────────────────────────────────────────────────────────
create table maintenance_tickets (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  facility_sport_id uuid references facility_sports (id) on delete restrict,
  issue_category_id uuid not null references maintenance_issue_categories (id) on delete restrict,
  title text not null,
  description text not null,
  priority text not null default 'MEDIUM' check (priority in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  status text not null default 'REPORTED' check (status in ('REPORTED', 'ASSIGNED', 'SCHEDULED', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  reported_by uuid not null references profiles (id),
  reported_at timestamptz not null default now(),
  assigned_to uuid references profiles (id) on delete set null,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  actual_start timestamptz,
  actual_end timestamptz,
  estimated_cost_minor integer check (estimated_cost_minor is null or estimated_cost_minor >= 0),
  actual_cost_minor integer check (actual_cost_minor is null or actual_cost_minor >= 0),
  expense_id uuid references expenses (id) on delete set null,
  notes text,
  resolved_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint maintenance_tickets_schedule_check check (scheduled_end is null or scheduled_start is null or scheduled_end > scheduled_start),
  constraint maintenance_tickets_actual_check check (actual_end is null or actual_start is null or actual_end > actual_start)
);

create index maintenance_tickets_facility_id_idx on maintenance_tickets (facility_id);
create index maintenance_tickets_court_id_idx on maintenance_tickets (court_id);
create index maintenance_tickets_status_idx on maintenance_tickets (status);
create index maintenance_tickets_facility_status_idx on maintenance_tickets (facility_id, status);

-- Same integrity pattern as enforce_booking_court_consistency (0007): a
-- client can never attach a ticket to a court that isn't actually this
-- facility's, and facility_sport_id is always derived, never trusted.
create function enforce_maintenance_ticket_court_consistency() returns trigger
language plpgsql
as $$
declare c courts;
begin
  select * into c from courts where id = new.court_id;
  if c is null then
    raise exception 'court % does not exist', new.court_id using errcode = '23503';
  end if;
  if c.facility_id is distinct from new.facility_id then
    raise exception 'ticket facility_id must match its court''s facility_id' using errcode = '23514';
  end if;
  new.facility_sport_id := c.facility_sport_id;
  return new;
end;
$$;

create trigger maintenance_tickets_enforce_court_consistency
  before insert or update of court_id on maintenance_tickets
  for each row execute function enforce_maintenance_ticket_court_consistency();

create trigger maintenance_tickets_set_updated_at
  before update on maintenance_tickets
  for each row execute function set_updated_at();

alter table maintenance_tickets enable row level security;
create policy "maintenance_tickets_select_members" on maintenance_tickets for select
  using (is_facility_member(facility_id));
create policy "maintenance_tickets_write_staff" on maintenance_tickets for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));


-- ─────────────────────────────────────────────────────────────────────────
-- maintenance_blocks — the availability-facing record. Same GiST exclusion
-- pattern as bookings_no_overlap (0001): two ACTIVE blocks on the same
-- court can never overlap, enforced by Postgres itself.
-- ─────────────────────────────────────────────────────────────────────────
create table maintenance_blocks (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  ticket_id uuid not null references maintenance_tickets (id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ENDED', 'CANCELLED')),
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint maintenance_blocks_time_check check (end_time > start_time),
  constraint maintenance_blocks_no_overlap exclude using gist (
    court_id with =,
    tstzrange(start_time, end_time) with &&
  ) where (status = 'ACTIVE')
);

create index maintenance_blocks_ticket_id_idx on maintenance_blocks (ticket_id);
create index maintenance_blocks_court_time_idx on maintenance_blocks (court_id, start_time);
create index maintenance_blocks_facility_id_idx on maintenance_blocks (facility_id);

create trigger maintenance_blocks_set_updated_at
  before update on maintenance_blocks
  for each row execute function set_updated_at();

alter table maintenance_blocks enable row level security;
create policy "maintenance_blocks_select_members" on maintenance_blocks for select
  using (is_facility_member(facility_id));
create policy "maintenance_blocks_write_staff" on maintenance_blocks for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- court_has_active_maintenance_block — the one predicate every availability
-- write path below now also asks, exactly like court_has_active_membership_
-- window already does. Granted to anon too: the public booking page's
-- availability/creation RPCs run as anon and must see this the same way.
-- ─────────────────────────────────────────────────────────────────────────
create function court_has_active_maintenance_block(
  p_court_id uuid, p_start timestamptz, p_end timestamptz
) returns boolean
language sql
stable
as $$
  select exists (
    select 1 from maintenance_blocks mb
    where mb.court_id = p_court_id
      and mb.status = 'ACTIVE'
      and tstzrange(mb.start_time, mb.end_time) && tstzrange(p_start, p_end)
  );
$$;
grant execute on function court_has_active_maintenance_block(uuid, timestamptz, timestamptz) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- maintenance_ticket_activity — the audit trail (spec §20/§36).
-- ─────────────────────────────────────────────────────────────────────────
create table maintenance_ticket_activity (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references maintenance_tickets (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  event_type text not null check (event_type in (
    'CREATED', 'UPDATED', 'ASSIGNED', 'SCHEDULED', 'COURT_BLOCKED',
    'STATUS_CHANGED', 'MAINTENANCE_STARTED', 'NOTE_ADDED', 'COST_UPDATED',
    'BOOKING_CONFLICT_DETECTED', 'RESOLVED', 'COURT_REOPENED', 'REOPENED', 'CLOSED'
  )),
  actor_id uuid references profiles (id) on delete set null,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index maintenance_ticket_activity_ticket_id_idx on maintenance_ticket_activity (ticket_id, created_at);

alter table maintenance_ticket_activity enable row level security;
create policy "maintenance_activity_select_members" on maintenance_ticket_activity for select
  using (is_facility_member(facility_id));
create policy "maintenance_activity_write_staff" on maintenance_ticket_activity for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

create function log_maintenance_activity(
  p_ticket_id uuid, p_facility_id uuid, p_event_type text, p_note text default null, p_metadata jsonb default '{}'::jsonb
) returns void
language sql
as $$
  insert into maintenance_ticket_activity (ticket_id, facility_id, event_type, actor_id, note, metadata)
  values (p_ticket_id, p_facility_id, p_event_type, auth.uid(), p_note, coalesce(p_metadata, '{}'::jsonb));
$$;
grant execute on function log_maintenance_activity(uuid, uuid, text, text, jsonb) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- maintenance_ticket_attachments — metadata only. Bytes live in the
-- 'maintenance-attachments' Storage bucket created below.
-- ─────────────────────────────────────────────────────────────────────────
create table maintenance_ticket_attachments (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references maintenance_tickets (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  content_type text,
  size_bytes integer,
  uploaded_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index maintenance_ticket_attachments_ticket_id_idx on maintenance_ticket_attachments (ticket_id);

alter table maintenance_ticket_attachments enable row level security;
create policy "maintenance_attachments_select_members" on maintenance_ticket_attachments for select
  using (is_facility_member(facility_id));
create policy "maintenance_attachments_write_staff" on maintenance_ticket_attachments for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('maintenance-attachments', 'maintenance-attachments', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- Object path convention: '<facility_id>/<ticket_id>/<file>' — the first
-- path segment is the facility, so storage RLS is the same facility-member
-- check every other table already uses.
create policy "maintenance_attachments_storage_select" on storage.objects for select
  using (bucket_id = 'maintenance-attachments' and is_facility_member(((storage.foldername(name))[1])::uuid));
create policy "maintenance_attachments_storage_insert" on storage.objects for insert
  with check (bucket_id = 'maintenance-attachments' and has_facility_role(((storage.foldername(name))[1])::uuid, array['owner', 'manager', 'staff']::facility_role[]));
create policy "maintenance_attachments_storage_delete" on storage.objects for delete
  using (bucket_id = 'maintenance-attachments' and has_facility_role(((storage.foldername(name))[1])::uuid, array['owner', 'manager', 'staff']::facility_role[]));

create function add_maintenance_attachment(
  p_ticket_id uuid, p_storage_path text, p_file_name text, p_content_type text default null, p_size_bytes integer default null
) returns maintenance_ticket_attachments
language plpgsql
as $$
declare t maintenance_tickets; result maintenance_ticket_attachments;
begin
  select * into t from maintenance_tickets where id = p_ticket_id;
  if t.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  insert into maintenance_ticket_attachments (ticket_id, facility_id, storage_path, file_name, content_type, size_bytes, uploaded_by)
  values (p_ticket_id, t.facility_id, p_storage_path, p_file_name, p_content_type, p_size_bytes, auth.uid())
  returning * into result;
  return result;
end;
$$;
grant execute on function add_maintenance_attachment(uuid, text, text, text, integer) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- Booking-impact detection (spec §15/§16/§17). Pure overlap reads — the same
-- tstzrange && convention bookings_no_overlap and every other overlap check
-- in this schema already uses (a booking starting exactly when maintenance
-- ends does not overlap).
-- ═══════════════════════════════════════════════════════════════════════════
create function detect_maintenance_affected_bookings(
  p_court_id uuid, p_start timestamptz, p_end timestamptz, p_exclude_ticket_id uuid default null
) returns table (
  booking_id uuid, customer_type text, guest_name text, guest_phone text, member_id uuid,
  start_time timestamptz, end_time timestamptz, status text, payment_status text, amount_minor integer
)
language sql
stable
as $$
  select b.id, b.customer_type, b.guest_name, b.guest_phone, b.member_id,
         b.start_time, b.end_time, b.status::text, b.payment_status, b.amount_minor
  from bookings b
  where b.court_id = p_court_id
    and b.status in ('pending', 'confirmed')
    and tstzrange(b.start_time, b.end_time) && tstzrange(p_start, p_end);
$$;
grant execute on function detect_maintenance_affected_bookings(uuid, timestamptz, timestamptz, uuid) to authenticated;

-- Membership sessions overlapping the window — surfaced, never mutated
-- (spec §16: "do not delete membership session records").
create function detect_maintenance_affected_membership_sessions(
  p_court_id uuid, p_start timestamptz, p_end timestamptz, p_timezone text default 'Asia/Kolkata'
) returns table (
  batch_id uuid, batch_name text, session_date date, start_time time, end_time time,
  member_booked_count bigint, guest_booked_count bigint
)
language plpgsql
stable
as $$
begin
  return query
  select
    mb.id, mb.name,
    (p_start at time zone p_timezone)::date,
    mb.start_time, mb.end_time,
    coalesce((select count(*) from membership_session_bookings b
      join membership_sessions s on s.id = b.session_id
      where s.batch_id = mb.id and b.participant_type = 'MEMBER' and b.status = 'CONFIRMED'), 0)::bigint,
    coalesce((select count(*) from membership_session_bookings b
      join membership_sessions s on s.id = b.session_id
      where s.batch_id = mb.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'), 0)::bigint
  from membership_batches mb
  where mb.court_id = p_court_id
    and mb.status = 'ACTIVE'
    and extract(dow from (p_start at time zone p_timezone)) = any(mb.days_of_week)
    and mb.start_time < (p_end at time zone p_timezone)::time
    and mb.end_time > (p_start at time zone p_timezone)::time
    and mb.start_date <= (p_start at time zone p_timezone)::date
    and (mb.end_date is null or mb.end_date >= (p_start at time zone p_timezone)::date);
end;
$$;
grant execute on function detect_maintenance_affected_membership_sessions(uuid, timestamptz, timestamptz, text) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- Ticket lifecycle. Every write path is a single RPC (spec §7 pattern) —
-- never a client-side plain status update.
-- ═══════════════════════════════════════════════════════════════════════════

create function create_maintenance_ticket(
  p_facility_id uuid,
  p_court_id uuid,
  p_issue_category_id uuid,
  p_priority text,
  p_title text,
  p_description text,
  p_scheduled_start timestamptz default null,
  p_scheduled_end timestamptz default null,
  p_assigned_to uuid default null,
  p_estimated_cost_minor integer default null,
  p_notes text default null
) returns maintenance_tickets
language plpgsql
as $$
declare
  result maintenance_tickets;
  category maintenance_issue_categories;
  v_status text := 'REPORTED';
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'Title is required.' using errcode = '23514';
  end if;
  if trim(coalesce(p_description, '')) = '' then
    raise exception 'Description is required.' using errcode = '23514';
  end if;
  if p_priority not in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') then
    raise exception 'Unknown priority: %', p_priority using errcode = '23514';
  end if;
  select * into category from maintenance_issue_categories
    where id = p_issue_category_id and (facility_id is null or facility_id = p_facility_id) and is_active;
  if category.id is null then
    raise exception 'That issue category is not available for this facility.' using errcode = '23503';
  end if;
  if not exists (select 1 from courts where id = p_court_id and facility_id = p_facility_id) then
    raise exception 'That court does not belong to this facility.' using errcode = '23503';
  end if;
  if p_scheduled_start is not null and p_scheduled_end is not null then
    if p_scheduled_end <= p_scheduled_start then
      raise exception 'Scheduled end must be after scheduled start.' using errcode = '23514';
    end if;
    v_status := 'SCHEDULED';
  elsif p_assigned_to is not null then
    v_status := 'ASSIGNED';
  end if;

  insert into maintenance_tickets (
    facility_id, court_id, issue_category_id, priority, title, description,
    reported_by, assigned_to, scheduled_start, scheduled_end, estimated_cost_minor, notes, status
  ) values (
    p_facility_id, p_court_id, p_issue_category_id, p_priority, trim(p_title), trim(p_description),
    auth.uid(), p_assigned_to, p_scheduled_start, p_scheduled_end, p_estimated_cost_minor, nullif(trim(coalesce(p_notes, '')), ''), v_status
  ) returning * into result;

  perform log_maintenance_activity(result.id, p_facility_id, 'CREATED', 'Ticket reported: ' || result.title);
  if p_assigned_to is not null then
    perform log_maintenance_activity(result.id, p_facility_id, 'ASSIGNED', null, jsonb_build_object('assignedTo', p_assigned_to));
  end if;

  if v_status = 'SCHEDULED' then
    begin
      insert into maintenance_blocks (facility_id, court_id, ticket_id, start_time, end_time, created_by)
      values (p_facility_id, p_court_id, result.id, p_scheduled_start, p_scheduled_end, auth.uid());
    exception when exclusion_violation then
      raise exception 'Another maintenance block already exists for this court and time.' using errcode = '23514';
    end;
    perform log_maintenance_activity(result.id, p_facility_id, 'SCHEDULED', null,
      jsonb_build_object('start', p_scheduled_start, 'end', p_scheduled_end));
    perform log_maintenance_activity(result.id, p_facility_id, 'COURT_BLOCKED');

    if exists (select 1 from detect_maintenance_affected_bookings(p_court_id, p_scheduled_start, p_scheduled_end)) then
      perform log_maintenance_activity(result.id, p_facility_id, 'BOOKING_CONFLICT_DETECTED', null,
        jsonb_build_object('count', (select count(*) from detect_maintenance_affected_bookings(p_court_id, p_scheduled_start, p_scheduled_end))));
    end if;
  end if;

  return result;
end;
$$;
grant execute on function create_maintenance_ticket(uuid, uuid, uuid, text, text, text, timestamptz, timestamptz, uuid, integer, text) to authenticated;


create function update_maintenance_ticket(
  p_ticket_id uuid, p_title text, p_description text, p_issue_category_id uuid, p_priority text, p_notes text default null
) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status in ('CLOSED') then
    raise exception 'A closed ticket cannot be edited.' using errcode = '23514';
  end if;
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'Title is required.' using errcode = '23514';
  end if;
  if p_priority not in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') then
    raise exception 'Unknown priority: %', p_priority using errcode = '23514';
  end if;

  update maintenance_tickets
  set title = trim(p_title),
      description = trim(coalesce(p_description, description)),
      issue_category_id = coalesce(p_issue_category_id, issue_category_id),
      priority = p_priority,
      notes = nullif(trim(coalesce(p_notes, '')), '')
  where id = p_ticket_id
  returning * into result;

  perform log_maintenance_activity(result.id, result.facility_id, 'UPDATED');
  return result;
end;
$$;
grant execute on function update_maintenance_ticket(uuid, text, text, uuid, text, text) to authenticated;


create function assign_maintenance_ticket(p_ticket_id uuid, p_assigned_to uuid) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets; v_status text;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status in ('RESOLVED', 'CLOSED') then
    raise exception 'Cannot assign a % ticket.', existing.status using errcode = '23514';
  end if;
  if not exists (select 1 from facility_users where facility_id = existing.facility_id and user_id = p_assigned_to) then
    raise exception 'That user is not a member of this facility.' using errcode = '23503';
  end if;

  v_status := case when existing.status = 'REPORTED' then 'ASSIGNED' else existing.status end;

  update maintenance_tickets set assigned_to = p_assigned_to, status = v_status
  where id = p_ticket_id
  returning * into result;

  perform log_maintenance_activity(result.id, result.facility_id, 'ASSIGNED', null, jsonb_build_object('assignedTo', p_assigned_to));
  return result;
end;
$$;
grant execute on function assign_maintenance_ticket(uuid, uuid) to authenticated;


-- schedule_maintenance: creates (or moves) the ticket's maintenance block.
-- Superseding a still-ACTIVE block for the same ticket rather than stacking
-- one — the exclusion constraint is what actually stops two DIFFERENT
-- tickets fighting over the same court/time.
create function schedule_maintenance(p_ticket_id uuid, p_start timestamptz, p_end timestamptz) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id for update;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status in ('RESOLVED', 'CLOSED') then
    raise exception 'Cannot schedule a % ticket.', existing.status using errcode = '23514';
  end if;
  if p_end <= p_start then
    raise exception 'Scheduled end must be after scheduled start.' using errcode = '23514';
  end if;

  update maintenance_blocks set status = 'ENDED', updated_at = now()
  where ticket_id = p_ticket_id and status = 'ACTIVE';

  begin
    insert into maintenance_blocks (facility_id, court_id, ticket_id, start_time, end_time, created_by)
    values (existing.facility_id, existing.court_id, p_ticket_id, p_start, p_end, auth.uid());
  exception when exclusion_violation then
    raise exception 'Another maintenance block already exists for this court and time.' using errcode = '23514';
  end;

  update maintenance_tickets
  set scheduled_start = p_start, scheduled_end = p_end,
      status = case when status in ('REPORTED', 'ASSIGNED') then 'SCHEDULED' else status end
  where id = p_ticket_id
  returning * into result;

  perform log_maintenance_activity(result.id, result.facility_id, 'SCHEDULED', null, jsonb_build_object('start', p_start, 'end', p_end));
  perform log_maintenance_activity(result.id, result.facility_id, 'COURT_BLOCKED');

  if exists (select 1 from detect_maintenance_affected_bookings(existing.court_id, p_start, p_end, p_ticket_id)) then
    perform log_maintenance_activity(result.id, result.facility_id, 'BOOKING_CONFLICT_DETECTED', null,
      jsonb_build_object('count', (select count(*) from detect_maintenance_affected_bookings(existing.court_id, p_start, p_end, p_ticket_id))));
  end if;

  return result;
end;
$$;
grant execute on function schedule_maintenance(uuid, timestamptz, timestamptz) to authenticated;


create function start_maintenance_ticket(p_ticket_id uuid) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status not in ('ASSIGNED', 'SCHEDULED') then
    raise exception 'Only an assigned or scheduled ticket can be started.' using errcode = '23514';
  end if;

  update maintenance_tickets set status = 'IN_PROGRESS', actual_start = now()
  where id = p_ticket_id
  returning * into result;

  perform log_maintenance_activity(result.id, result.facility_id, 'MAINTENANCE_STARTED');
  return result;
end;
$$;
grant execute on function start_maintenance_ticket(uuid) to authenticated;


create function add_maintenance_note(p_ticket_id uuid, p_note text) returns maintenance_ticket_activity
language plpgsql
as $$
declare t maintenance_tickets; result maintenance_ticket_activity;
begin
  select * into t from maintenance_tickets where id = p_ticket_id;
  if t.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if trim(coalesce(p_note, '')) = '' then
    raise exception 'Note cannot be empty.' using errcode = '23514';
  end if;
  insert into maintenance_ticket_activity (ticket_id, facility_id, event_type, actor_id, note)
  values (p_ticket_id, t.facility_id, 'NOTE_ADDED', auth.uid(), trim(p_note))
  returning * into result;
  return result;
end;
$$;
grant execute on function add_maintenance_note(uuid, text) to authenticated;


-- update_maintenance_cost: when p_post_to_expenses posts the actual cost
-- through the EXISTING create_expense (0046) — never a second ledger. The
-- ticket's expense_id links back for Reports/Finance to trace the source.
create function update_maintenance_cost(
  p_ticket_id uuid,
  p_estimated_cost_minor integer default null,
  p_actual_cost_minor integer default null,
  p_post_to_expenses boolean default false,
  p_expense_category_id uuid default null,
  p_payment_method text default null,
  p_vendor text default null
) returns maintenance_tickets
language plpgsql
as $$
declare
  existing maintenance_tickets;
  result maintenance_tickets;
  cat_id uuid;
  exp expenses;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;

  update maintenance_tickets
  set estimated_cost_minor = coalesce(p_estimated_cost_minor, estimated_cost_minor),
      actual_cost_minor = coalesce(p_actual_cost_minor, actual_cost_minor)
  where id = p_ticket_id
  returning * into result;

  if p_post_to_expenses and result.actual_cost_minor is not null and result.expense_id is null then
    cat_id := p_expense_category_id;
    if cat_id is null then
      select id into cat_id from expense_categories
        where lower(name) = 'maintenance' and (facility_id is null or facility_id = result.facility_id)
        order by facility_id nulls last limit 1;
    end if;
    exp := create_expense(result.facility_id, cat_id, result.actual_cost_minor, current_date, p_payment_method, p_vendor, 'MT-' || substr(replace(result.id::text, '-', ''), 1, 8), 'Maintenance: ' || result.title);
    update maintenance_tickets set expense_id = exp.id where id = p_ticket_id returning * into result;
  end if;

  perform log_maintenance_activity(result.id, result.facility_id, 'COST_UPDATED', null,
    jsonb_build_object('estimatedCostMinor', result.estimated_cost_minor, 'actualCostMinor', result.actual_cost_minor, 'expenseId', result.expense_id));
  return result;
end;
$$;
grant execute on function update_maintenance_cost(uuid, integer, integer, boolean, uuid, text, text) to authenticated;


-- resolve_maintenance_ticket: ends the ticket's active block — the court's
-- availability is recalculated for free the instant this commits, because
-- every availability read filters status = 'ACTIVE'. No separate
-- "recalculate availability" step exists because none is needed.
create function resolve_maintenance_ticket(p_ticket_id uuid, p_actual_end timestamptz default null) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id for update;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status not in ('IN_PROGRESS', 'SCHEDULED', 'ASSIGNED') then
    raise exception 'Cannot resolve a % ticket.', existing.status using errcode = '23514';
  end if;

  update maintenance_tickets
  set status = 'RESOLVED',
      actual_start = coalesce(actual_start, now()),
      actual_end = coalesce(p_actual_end, now()),
      resolved_at = now()
  where id = p_ticket_id
  returning * into result;

  update maintenance_blocks set status = 'ENDED', updated_at = now()
  where ticket_id = p_ticket_id and status = 'ACTIVE';

  perform log_maintenance_activity(result.id, result.facility_id, 'RESOLVED');
  perform log_maintenance_activity(result.id, result.facility_id, 'COURT_REOPENED');
  return result;
end;
$$;
grant execute on function resolve_maintenance_ticket(uuid, timestamptz) to authenticated;


create function reopen_maintenance_ticket(p_ticket_id uuid) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(existing.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized to reopen this ticket.' using errcode = '42501';
  end if;
  if existing.status <> 'RESOLVED' then
    raise exception 'Only a resolved ticket can be reopened.' using errcode = '23514';
  end if;

  update maintenance_tickets set status = 'IN_PROGRESS', resolved_at = null
  where id = p_ticket_id
  returning * into result;

  perform log_maintenance_activity(result.id, result.facility_id, 'REOPENED');
  return result;
end;
$$;
grant execute on function reopen_maintenance_ticket(uuid) to authenticated;


create function close_maintenance_ticket(p_ticket_id uuid, p_reason text default null) returns maintenance_tickets
language plpgsql
as $$
declare existing maintenance_tickets; result maintenance_tickets;
begin
  select * into existing from maintenance_tickets where id = p_ticket_id for update;
  if existing.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if existing.status = 'CLOSED' then
    return existing;
  end if;

  update maintenance_tickets set status = 'CLOSED', closed_at = now()
  where id = p_ticket_id
  returning * into result;

  update maintenance_blocks set status = 'CANCELLED', updated_at = now()
  where ticket_id = p_ticket_id and status = 'ACTIVE';

  perform log_maintenance_activity(result.id, result.facility_id, 'CLOSED', p_reason);
  return result;
end;
$$;
grant execute on function close_maintenance_ticket(uuid, text) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- Reads — list, detail, court status, overview. Explicit has_facility_role
-- checks (not just RLS) on every aggregate, matching Finance's own "clear
-- denial, not a silent zero" rule (0024).
-- ═══════════════════════════════════════════════════════════════════════════

create function list_maintenance_tickets(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_priority text default null,
  p_court_id uuid default null,
  p_facility_sport_id uuid default null,
  p_issue_category_id uuid default null,
  p_assigned_to uuid default null,
  p_from date default null,
  p_to date default null,
  p_sort text default 'NEWEST',
  p_limit integer default 20,
  p_offset integer default 0
) returns table (
  ticket_id uuid, code text, court_id uuid, court_name text, sport_name text,
  issue_category_id uuid, category_name text, title text, priority text, status text,
  reported_by_name text, assigned_to_name text, scheduled_start timestamptz,
  reported_at timestamptz, actual_cost_minor integer, estimated_cost_minor integer,
  total_count bigint
)
language plpgsql
stable
as $$
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  return query
  select
    t.id, 'MT-' || upper(substr(replace(t.id::text, '-', ''), 1, 4)),
    c.id, c.name, coalesce(fs.custom_sport_name, sp.name),
    cat.id, cat.name, t.title, t.priority, t.status,
    rp.full_name, ap.full_name, t.scheduled_start, t.reported_at,
    t.actual_cost_minor, t.estimated_cost_minor,
    count(*) over () as total_count
  from maintenance_tickets t
  join courts c on c.id = t.court_id
  left join facility_sports fs on fs.id = t.facility_sport_id
  left join sports sp on sp.id = fs.sport_id
  join maintenance_issue_categories cat on cat.id = t.issue_category_id
  join profiles rp on rp.id = t.reported_by
  left join profiles ap on ap.id = t.assigned_to
  where t.facility_id = p_facility_id
    and (p_status is null or t.status = p_status)
    and (p_priority is null or t.priority = p_priority)
    and (p_court_id is null or t.court_id = p_court_id)
    and (p_facility_sport_id is null or t.facility_sport_id = p_facility_sport_id)
    and (p_issue_category_id is null or t.issue_category_id = p_issue_category_id)
    and (p_assigned_to is null or t.assigned_to = p_assigned_to)
    and (p_from is null or t.reported_at::date >= p_from)
    and (p_to is null or t.reported_at::date <= p_to)
    and (
      p_search is null or trim(p_search) = '' or
      t.title ilike '%' || trim(p_search) || '%' or
      c.name ilike '%' || trim(p_search) || '%' or
      ('MT-' || upper(substr(replace(t.id::text, '-', ''), 1, 4))) ilike '%' || trim(p_search) || '%'
    )
  order by
    case when p_sort = 'PRIORITY' then
      case t.priority when 'CRITICAL' then 0 when 'HIGH' then 1 when 'MEDIUM' then 2 else 3 end
    end asc nulls last,
    case when p_sort = 'OLDEST' then t.reported_at end asc nulls last,
    t.reported_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;
grant execute on function list_maintenance_tickets(uuid, text, text, text, uuid, uuid, uuid, uuid, date, date, text, integer, integer) to authenticated;


-- get_maintenance_ticket_detail: one aggregate jsonb read for the Ticket
-- Details page — ticket + names + active block + attachments + activity +
-- affected bookings/sessions, in one round trip.
create function get_maintenance_ticket_detail(p_ticket_id uuid) returns jsonb
language plpgsql
stable
as $$
declare
  t maintenance_tickets;
  fac facilities;
begin
  select * into t from maintenance_tickets where id = p_ticket_id;
  if t.id is null then
    raise exception 'Maintenance ticket not found' using errcode = 'P0002';
  end if;
  if not is_facility_member(t.facility_id) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select * into fac from facilities where id = t.facility_id;

  return jsonb_build_object(
    'id', t.id,
    'code', 'MT-' || upper(substr(replace(t.id::text, '-', ''), 1, 4)),
    'facilityId', t.facility_id,
    'court', (select jsonb_build_object('id', c.id, 'name', c.name) from courts c where c.id = t.court_id),
    'sportName', (select coalesce(fs.custom_sport_name, sp.name) from facility_sports fs join sports sp on sp.id = fs.sport_id where fs.id = t.facility_sport_id),
    'category', (select jsonb_build_object('id', cat.id, 'name', cat.name, 'icon', cat.icon) from maintenance_issue_categories cat where cat.id = t.issue_category_id),
    'title', t.title,
    'description', t.description,
    'priority', t.priority,
    'status', t.status,
    'reportedBy', (select jsonb_build_object('id', p.id, 'name', p.full_name) from profiles p where p.id = t.reported_by),
    'reportedAt', t.reported_at,
    'assignedTo', (select jsonb_build_object('id', p.id, 'name', p.full_name) from profiles p where p.id = t.assigned_to),
    'scheduledStart', t.scheduled_start,
    'scheduledEnd', t.scheduled_end,
    'actualStart', t.actual_start,
    'actualEnd', t.actual_end,
    'estimatedCostMinor', t.estimated_cost_minor,
    'actualCostMinor', t.actual_cost_minor,
    'expenseId', t.expense_id,
    'notes', t.notes,
    'currency', coalesce(fac.currency, 'INR'),
    'activeBlock', (
      select jsonb_build_object('id', mb.id, 'startTime', mb.start_time, 'endTime', mb.end_time, 'status', mb.status)
      from maintenance_blocks mb where mb.ticket_id = t.id and mb.status = 'ACTIVE' order by mb.created_at desc limit 1
    ),
    'attachments', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'storagePath', a.storage_path, 'fileName', a.file_name, 'contentType', a.content_type, 'sizeBytes', a.size_bytes, 'createdAt', a.created_at) order by a.created_at)
      from maintenance_ticket_attachments a where a.ticket_id = t.id
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'eventType', e.event_type, 'note', e.note, 'metadata', e.metadata, 'actorName', p.full_name, 'createdAt', e.created_at) order by e.created_at desc)
      from maintenance_ticket_activity e left join profiles p on p.id = e.actor_id where e.ticket_id = t.id
    ), '[]'::jsonb),
    'affectedBookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'bookingId', b.booking_id, 'customerType', b.customer_type, 'guestName', b.guest_name, 'memberId', b.member_id,
        'startTime', b.start_time, 'endTime', b.end_time, 'status', b.status, 'paymentStatus', b.payment_status, 'amountMinor', b.amount_minor
      ))
      from detect_maintenance_affected_bookings(t.court_id, coalesce(t.scheduled_start, now()), coalesce(t.scheduled_end, now())) b
      where t.scheduled_start is not null and t.scheduled_end is not null
    ), '[]'::jsonb),
    'affectedSessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'batchId', s.batch_id, 'batchName', s.batch_name, 'sessionDate', s.session_date,
        'startTime', s.start_time, 'endTime', s.end_time, 'memberBookedCount', s.member_booked_count, 'guestBookedCount', s.guest_booked_count
      ))
      from detect_maintenance_affected_membership_sessions(t.court_id, coalesce(t.scheduled_start, now()), coalesce(t.scheduled_end, now()), coalesce(fac.timezone, 'Asia/Kolkata')) s
      where t.scheduled_start is not null and t.scheduled_end is not null
    ), '[]'::jsonb)
  );
end;
$$;
grant execute on function get_maintenance_ticket_detail(uuid) to authenticated;


-- get_maintenance_court_status: feeds Overview's Court Status grid.
create function get_maintenance_court_status(p_facility_id uuid) returns table (
  court_id uuid, court_name text, sport_name text, status text
)
language plpgsql
stable
as $$
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  return query
  select
    c.id, c.name, coalesce(fs.custom_sport_name, sp.name),
    case
      when not c.booking_enabled or c.archived or c.status <> 'ACTIVE' then 'BLOCKED'
      when exists (select 1 from maintenance_blocks mb where mb.court_id = c.id and mb.status = 'ACTIVE' and tstzrange(mb.start_time, mb.end_time) @> now()) then 'UNDER_MAINTENANCE'
      when exists (select 1 from bookings b where b.court_id = c.id and b.status in ('pending', 'confirmed') and tstzrange(b.start_time, b.end_time) @> now()) then 'IN_USE'
      else 'AVAILABLE'
    end
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  where c.facility_id = p_facility_id and not c.archived
  order by c.display_order, c.name;
end;
$$;
grant execute on function get_maintenance_court_status(uuid) to authenticated;


-- get_maintenance_overview: one aggregate jsonb read for the whole
-- dashboard — KPIs, court status, recent tickets, upcoming schedule, recent
-- activity, repair cost this month (from the SAME payments/expenses source
-- Finance already reports from — see update_maintenance_cost above).
create function get_maintenance_overview(p_facility_id uuid) returns jsonb
language plpgsql
stable
as $$
declare
  month_start date := date_trunc('month', current_date)::date;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'openIssues', (select count(*) from maintenance_tickets where facility_id = p_facility_id and status in ('REPORTED')),
    'inProgress', (select count(*) from maintenance_tickets where facility_id = p_facility_id and status = 'IN_PROGRESS'),
    'scheduled', (select count(*) from maintenance_tickets where facility_id = p_facility_id and status = 'SCHEDULED'),
    'resolvedThisMonth', (select count(*) from maintenance_tickets where facility_id = p_facility_id and status in ('RESOLVED', 'CLOSED') and resolved_at >= month_start),
    'courtsBlocked', (select count(distinct court_id) from maintenance_blocks where facility_id = p_facility_id and status = 'ACTIVE' and tstzrange(start_time, end_time) @> now()),
    'repairCostThisMonthMinor', coalesce((select sum(actual_cost_minor) from maintenance_tickets where facility_id = p_facility_id and actual_cost_minor is not null and reported_at >= month_start), 0),
    'courtStatus', coalesce((select jsonb_agg(jsonb_build_object('courtId', s.court_id, 'courtName', s.court_name, 'sportName', s.sport_name, 'status', s.status)) from get_maintenance_court_status(p_facility_id) s), '[]'::jsonb),
    'recentTickets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ticketId', r.ticket_id, 'code', r.code, 'courtName', r.court_name, 'title', r.title,
        'priority', r.priority, 'status', r.status, 'reportedAt', r.reported_at, 'assignedToName', r.assigned_to_name
      )) from list_maintenance_tickets(p_facility_id, null, null, null, null, null, null, null, null, null, 'NEWEST', 8, 0) r
    ), '[]'::jsonb),
    'upcomingSchedule', coalesce((
      select jsonb_agg(jsonb_build_object('ticketId', mb.ticket_id, 'courtName', c.name, 'title', t.title, 'startTime', mb.start_time, 'endTime', mb.end_time) order by mb.start_time)
      from maintenance_blocks mb join courts c on c.id = mb.court_id join maintenance_tickets t on t.id = mb.ticket_id
      where mb.facility_id = p_facility_id and mb.status = 'ACTIVE' and mb.end_time > now()
    ), '[]'::jsonb),
    'recentActivity', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'ticketId', e.ticket_id, 'eventType', e.event_type, 'note', e.note, 'actorName', p.full_name, 'createdAt', e.created_at) order by e.created_at desc)
      from (select * from maintenance_ticket_activity where facility_id = p_facility_id order by created_at desc limit 8) e
      left join profiles p on p.id = e.actor_id
    ), '[]'::jsonb)
  );
end;
$$;
grant execute on function get_maintenance_overview(uuid) to authenticated;


-- list_facility_staff: the ticket Assignment step's staff picker. Reuses
-- the existing facility_users/profiles tables — no new Users/Roles system.
create function list_facility_staff(p_facility_id uuid) returns table (
  user_id uuid, full_name text, role facility_role
)
language sql
stable
as $$
  select p.id, p.full_name, fu.role
  from facility_users fu
  join profiles p on p.id = fu.user_id
  where fu.facility_id = p_facility_id and is_facility_member(p_facility_id)
  order by fu.role, p.full_name;
$$;
grant execute on function list_facility_staff(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- Availability engine integration — the whole point of this migration.
-- create_booking / reschedule_booking / get_public_court_availability are
-- restated with exactly one addition each: a
-- court_has_active_maintenance_block check, in the same place and the same
-- shape as the existing court_has_active_membership_window check. Every
-- other line is byte-identical to the current definitions (0040 for
-- create_booking, 0014 for reschedule_booking, 0045 for
-- get_public_court_availability).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function create_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_customer_type text,
  p_member_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_notes text,
  p_payment_status text default 'PENDING',
  p_guest_player_id uuid default null,
  p_party_size integer default 1,
  p_payment_method text default null
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
  guest guest_players;
  v_guest_name text := p_guest_name;
  v_guest_phone text := p_guest_phone;
begin
  if p_end_time <= p_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'facility % does not exist', p_facility_id using errcode = '23503';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_court_id using errcode = '23503';
  end if;

  if p_guest_player_id is not null then
    select * into guest from guest_players where id = p_guest_player_id and facility_id = p_facility_id;
    if guest.id is null then
      raise exception 'guest % does not exist for this facility', p_guest_player_id using errcode = '23503';
    end if;
    v_guest_name := guest.name;
    v_guest_phone := guest.phone;
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  if court_has_active_maintenance_block(p_court_id, p_start_time, p_end_time) then
    raise exception 'This court is under maintenance during the selected time.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, guest_player_id,
    amount_minor, currency, notes, created_by, payment_status,
    party_size, payment_method
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), v_guest_name, v_guest_phone, p_guest_player_id,
    price, fac.currency, p_notes, auth.uid(), coalesce(p_payment_status, 'PENDING'),
    greatest(coalesce(p_party_size, 1), 1), nullif(trim(p_payment_method), '')
  ) returning * into result;

  return result;
end;
$$;
grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text, uuid, integer, text) to authenticated;


create or replace function reschedule_booking(
  p_booking_id uuid,
  p_new_court_id uuid,
  p_new_start_time timestamptz,
  p_new_end_time timestamptz
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
begin
  if p_new_end_time <= p_new_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into result from bookings where id = p_booking_id;
  if result.id is null then
    raise exception 'booking % does not exist', p_booking_id using errcode = '23503';
  end if;
  if result.status not in ('pending', 'confirmed') then
    raise exception 'Only a pending or confirmed booking can be rescheduled.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = result.facility_id;
  select * into court from courts where id = p_new_court_id and facility_id = result.facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_new_court_id using errcode = '23503';
  end if;

  if not booking_window_fits_operating_hours(result.facility_id, p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  if court_has_active_maintenance_block(p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'This court is under maintenance during the selected time.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone);

  update bookings
  set court_id = p_new_court_id,
      start_time = p_new_start_time,
      end_time = p_new_end_time,
      amount_minor = price
  where id = p_booking_id
  returning * into result;

  return result;
end;
$$;
grant execute on function reschedule_booking(uuid, uuid, timestamptz, timestamptz) to authenticated;


create or replace function get_public_court_availability(
  p_facility_id uuid,
  p_facility_sport_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fac facilities;
  tz text;
  result jsonb := '[]'::jsonb;
  c record;
  h integer;
  slot_start timestamptz;
  slot_end timestamptz;
  slots jsonb;
  released integer;
  guest_booked integer;
  is_available boolean;
  price integer;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    return '[]'::jsonb;
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  for c in
    select ct.id, ct.name
    from courts ct
    where ct.facility_id = p_facility_id
      and ct.facility_sport_id = p_facility_sport_id
      and not ct.archived
    order by ct.display_order, ct.name
  loop
    slots := '[]'::jsonb;

    for h in 0..23 loop
      slot_start := (p_date::text || ' ' || lpad(h::text, 2, '0') || ':00:00')::timestamp at time zone tz;
      slot_end := slot_start + interval '1 hour';

      continue when slot_end <= now();
      continue when not booking_window_fits_operating_hours(p_facility_id, c.id, slot_start, slot_end);

      is_available := not exists (
        select 1
        from bookings b
        where b.court_id = c.id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.start_time, b.end_time) && tstzrange(slot_start, slot_end)
      );

      if is_available and court_has_active_maintenance_block(c.id, slot_start, slot_end) then
        is_available := false;
      end if;

      if is_available and court_has_active_membership_window(c.id, slot_start, slot_end, tz) then
        select
          coalesce(ms.released_capacity, 0),
          coalesce((
            select count(*)
            from membership_session_bookings msb
            where msb.session_id = ms.id
              and msb.participant_type = 'GUEST'
              and msb.status = 'CONFIRMED'
          ), 0)
        into released, guest_booked
        from membership_batches mb
        left join membership_sessions ms
          on ms.batch_id = mb.id and ms.session_date = p_date
        where mb.court_id = c.id
          and mb.status = 'ACTIVE'
          and extract(dow from (slot_start at time zone tz)) = any(mb.days_of_week)
          and mb.start_time < (slot_end at time zone tz)::time
          and mb.end_time > (slot_start at time zone tz)::time
          and mb.start_date <= p_date
          and (mb.end_date is null or mb.end_date >= p_date)
          and not exists (
            select 1 from membership_batch_blocked_dates bd
            where bd.batch_id = mb.id and bd.blocked_date = p_date
          )
        limit 1;

        is_available := coalesce(released, 0) > coalesce(guest_booked, 0);
      end if;

      price := resolve_booking_price(p_facility_sport_id, c.id, slot_start, slot_end, tz);

      slots := slots || jsonb_build_object(
        'startTime', slot_start,
        'endTime', slot_end,
        'available', is_available,
        'priceMinor', coalesce(price, 0)
      );
    end loop;

    if jsonb_array_length(slots) > 0 then
      result := result || jsonb_build_object(
        'courtId', c.id,
        'courtName', c.name,
        'slots', slots
      );
    end if;
  end loop;

  return result;
end;
$$;
grant execute on function get_public_court_availability(uuid, uuid, date) to anon, authenticated;
