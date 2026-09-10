import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import { authed, closeAll, makeFacility, makeUser, resetCore, superuser } from "./_helpers.ts";

// Inventory & Vendors (migrations 0078-0081) — the spec's required tests
// (§69-72). Stock integrity, purchase→finance separation, RLS, permissions.

type SU = Awaited<ReturnType<typeof superuser>>;

async function addStaff(su: SU, facilityId: string, userId: string, role: "owner" | "manager" | "staff") {
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, status, is_primary, activated_at)
           values ($1, $2, $3, 'ACTIVE', false, now())`,
    args: [facilityId, userId, role],
  });
}

async function seed(su: SU) {
  await resetCore(su);
  await su.queryArray(
    `delete from inventory_events; delete from inventory_movements; delete from purchase_order_items;
     delete from purchase_orders; delete from purchase_order_items;
     delete from inventory_items where facility_id is not null;
     delete from inventory_categories; delete from vendors;`,
  );
  const owner = await makeUser(su);
  const facilityId = await makeFacility(su, owner);
  return { owner, facilityId };
}

async function category(c: Awaited<ReturnType<typeof authed>>, facilityId: string, name = "Shuttles"): Promise<string> {
  return (
    await c.queryObject<{ id: string }>({
      text: `select (create_inventory_category($1, $2)).id as id`,
      args: [facilityId, name],
    })
  ).rows[0].id;
}

async function item(
  c: Awaited<ReturnType<typeof authed>>,
  facilityId: string,
  catId: string,
  opening = 0,
  sku = "SH-001",
): Promise<string> {
  return (
    await c.queryObject<{ id: string }>({
      text: `select (create_inventory_item($1, 'Yonex Shuttle', $2, $3, 'piece', 20, null, null, 80000, null, null, $4)).id as id`,
      args: [facilityId, sku, catId, opening],
    })
  ).rows[0].id;
}

Deno.test("item: duplicate SKU in the same facility is rejected server-side", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  await item(c, facilityId, cat, 0, "SH-001");
  await assertRejects(
    () => c.queryArray({ text: `select create_inventory_item($1,'Other','SH-001',$2,'piece',5)`, args: [facilityId, cat] }),
    Error,
    "SKU already exists",
  );
  await closeAll(su, c);
});

Deno.test("stock: in, out, adjustment update current_stock and write a signed ledger row", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  const it = await item(c, facilityId, cat, 0);

  await c.queryArray({ text: `select record_stock_movement($1,'STOCK_IN',10,'Replenishment',null,75000)`, args: [it] });
  await c.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',5,'Used at desk')`, args: [it] });
  await c.queryArray({ text: `select record_stock_movement($1,'ADJUSTMENT',-2,'Physical count')`, args: [it] });

  const stock = await c.queryObject<{ current_stock: number; unit_cost_minor: number }>({
    text: `select current_stock, unit_cost_minor from inventory_items where id = $1`,
    args: [it],
  });
  assertEquals(stock.rows[0].current_stock, 3);

  const moves = await c.queryObject<{ n: bigint; bal: number }>({
    text: `select count(*)::bigint n, (array_agg(balance_after order by created_at))[3] bal from inventory_movements where item_id = $1`,
    args: [it],
  });
  assertEquals(Number(moves.rows[0].n), 3);
  assertEquals(moves.rows[0].bal, 3);
  await closeAll(su, c);
});

Deno.test("stock out cannot exceed available stock (no negative inventory)", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  const it = await item(c, facilityId, cat, 5);
  await assertRejects(
    () => c.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',8)`, args: [it] }),
    Error,
    "Only 5 unit",
  );
  await closeAll(su, c);
});

Deno.test("concurrent stock-outs can never drive the balance negative", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const setup = await authed(owner);
  const cat = await category(setup, facilityId);
  const it = await item(setup, facilityId, cat, 10);
  await setup.end();

  const a = await authed(owner);
  const b = await authed(owner);
  const results = await Promise.allSettled([
    a.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',7)`, args: [it] }),
    b.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',6)`, args: [it] }),
  ]);
  const ok = results.filter((r) => r.status === "fulfilled").length;
  assertEquals(ok, 1); // both can't be satisfied from 10

  const stock = (
    await su.queryObject<{ n: number }>({ text: `select current_stock n from inventory_items where id = $1`, args: [it] })
  ).rows[0].n;
  assert(stock >= 0);
  await closeAll(su, a, b);
});

Deno.test("purchase order: partial then full receiving moves stock and advances status", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  const it = await item(c, facilityId, cat, 0);
  const vendorId = (
    await c.queryObject<{ id: string }>({ text: `select (create_vendor($1,'RK Sports')).id id`, args: [facilityId] })
  ).rows[0].id;

  const po = await c.queryObject<{ id: string }>({
    text: `select (create_purchase_order($1, $2, $3::jsonb)).id as id`,
    args: [facilityId, vendorId, JSON.stringify([{ itemId: it, quantity: 50, unitCostMinor: 80000 }])],
  });
  const poId = po.rows[0].id;
  await c.queryArray({ text: `select place_purchase_order($1)`, args: [poId] });

  const lineId = (
    await su.queryObject<{ id: string }>({
      text: `select id from purchase_order_items where purchase_order_id = $1`,
      args: [poId],
    })
  ).rows[0].id;

  await c.queryArray({
    text: `select receive_purchase_order($1, $2::jsonb)`,
    args: [poId, JSON.stringify([{ lineId, quantity: 30 }])],
  });
  let po2 = await su.queryObject<{ status: string }>({ text: `select status from purchase_orders where id = $1`, args: [poId] });
  assertEquals(po2.rows[0].status, "PARTIALLY_RECEIVED");
  assertEquals(
    (await su.queryObject<{ n: number }>({ text: `select current_stock n from inventory_items where id = $1`, args: [it] })).rows[0].n,
    30,
  );

  // Cannot over-receive the remaining 20.
  await assertRejects(
    () => c.queryArray({ text: `select receive_purchase_order($1,$2::jsonb)`, args: [poId, JSON.stringify([{ lineId, quantity: 25 }])] }),
    Error,
    "more than the",
  );

  await c.queryArray({ text: `select receive_purchase_order($1,$2::jsonb)`, args: [poId, JSON.stringify([{ lineId, quantity: 20 }])] });
  po2 = await su.queryObject({ text: `select status from purchase_orders where id = $1`, args: [poId] });
  assertEquals(po2.rows[0].status, "RECEIVED");
  assertEquals(
    (await su.queryObject<{ n: number }>({ text: `select current_stock n from inventory_items where id = $1`, args: [it] })).rows[0].n,
    50,
  );
  await closeAll(su, c);
});

Deno.test("placing a PO creates ONE pending expense — receiving does not make it paid", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  const it = await item(c, facilityId, cat, 0);
  const vendorId = (await c.queryObject<{ id: string }>({ text: `select (create_vendor($1,'RK Sports')).id id`, args: [facilityId] })).rows[0].id;
  const poId = (
    await c.queryObject<{ id: string }>({
      text: `select (create_purchase_order($1,$2,$3::jsonb)).id id`,
      args: [facilityId, vendorId, JSON.stringify([{ itemId: it, quantity: 10, unitCostMinor: 80000 }])],
    })
  ).rows[0].id;
  await c.queryArray({ text: `select place_purchase_order($1)`, args: [poId] });

  const exp = await su.queryObject<{ n: bigint; amt: number; ps: string }>({
    text: `select count(*)::bigint n, max(e.amount_minor) amt, max(e.payment_status) ps
           from purchase_orders po join expenses e on e.id = po.expense_id where po.id = $1`,
    args: [poId],
  });
  assertEquals(Number(exp.rows[0].n), 1);
  assertEquals(exp.rows[0].amt, 800000);
  assertEquals(exp.rows[0].ps, "PENDING");

  const lineId = (await su.queryObject<{ id: string }>({ text: `select id from purchase_order_items where purchase_order_id=$1`, args: [poId] })).rows[0].id;
  await c.queryArray({ text: `select receive_purchase_order($1,$2::jsonb)`, args: [poId, JSON.stringify([{ lineId, quantity: 10 }])] });
  const still = await su.queryObject<{ ps: string }>({
    text: `select e.payment_status ps from purchase_orders po join expenses e on e.id=po.expense_id where po.id=$1`,
    args: [poId],
  });
  assertEquals(still.rows[0].ps, "PENDING"); // received != paid
  await closeAll(su, c);
});

Deno.test("PURCHASE_CREATE without FINANCE_RECORD_PAYMENT cannot mark a purchase paid", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const oc = await authed(owner);
  const cat = await category(oc, facilityId);
  const it = await item(oc, facilityId, cat, 0);
  const vendorId = (await oc.queryObject<{ id: string }>({ text: `select (create_vendor($1,'RK')).id id`, args: [facilityId] })).rows[0].id;
  const poId = (
    await oc.queryObject<{ id: string }>({
      text: `select (create_purchase_order($1,$2,$3::jsonb)).id id`,
      args: [facilityId, vendorId, JSON.stringify([{ itemId: it, quantity: 5, unitCostMinor: 10000 }])],
    })
  ).rows[0].id;
  await oc.queryArray({ text: `select place_purchase_order($1)`, args: [poId] });

  // a custom-role staff with PURCHASE_* but no FINANCE_RECORD_PAYMENT
  const buyer = await makeUser(su);
  const roleId = (
    await su.queryObject<{ id: string }>({
      text: `insert into roles (facility_id, name, base_role, is_system) values ($1,'Buyer','staff',false) returning id`,
      args: [facilityId],
    })
  ).rows[0].id;
  await su.queryArray({
    text: `insert into role_permissions (role_id, permission_key) values ($1,'PURCHASE_VIEW'),($1,'PURCHASE_CREATE'),($1,'PURCHASE_RECEIVE'),($1,'INVENTORY_VIEW')`,
    args: [roleId],
  });
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role, role_id, status, activated_at) values ($1,$2,'staff',$3,'ACTIVE',now())`,
    args: [facilityId, buyer, roleId],
  });
  const bc = await authed(buyer);
  await assertRejects(
    () => bc.queryArray({ text: `select record_purchase_payment($1, 10000)`, args: [poId] }),
    Error,
    "permission to record payments",
  );
  await closeAll(su, oc, bc);
});

Deno.test("a fully received purchase order cannot be cancelled", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId);
  const it = await item(c, facilityId, cat, 0);
  const vendorId = (await c.queryObject<{ id: string }>({ text: `select (create_vendor($1,'RK')).id id`, args: [facilityId] })).rows[0].id;
  const poId = (
    await c.queryObject<{ id: string }>({
      text: `select (create_purchase_order($1,$2,$3::jsonb)).id id`,
      args: [facilityId, vendorId, JSON.stringify([{ itemId: it, quantity: 4, unitCostMinor: 10000 }])],
    })
  ).rows[0].id;
  await c.queryArray({ text: `select place_purchase_order($1)`, args: [poId] });
  const lineId = (await su.queryObject<{ id: string }>({ text: `select id from purchase_order_items where purchase_order_id=$1`, args: [poId] })).rows[0].id;
  await c.queryArray({ text: `select receive_purchase_order($1,$2::jsonb)`, args: [poId, JSON.stringify([{ lineId, quantity: 4 }])] });
  await assertRejects(
    () => c.queryArray({ text: `select cancel_purchase_order($1,'changed mind')`, args: [poId] }),
    Error,
    "fully received",
  );
  await closeAll(su, c);
});

Deno.test("maintenance stock-out records a movement referencing the ticket, no auto expense", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const c = await authed(owner);
  const cat = await category(c, facilityId, "Nets");
  const it = await item(c, facilityId, cat, 3, "NT-001");
  const ticketId = crypto.randomUUID();
  await c.queryArray({
    text: `select record_stock_movement($1,'STOCK_OUT',1,'Maintenance replacement',null,null,'maintenance_ticket',$2)`,
    args: [it, ticketId],
  });
  const m = await su.queryObject<{ rt: string; rid: string; q: number }>({
    text: `select reference_type rt, reference_id rid, quantity q from inventory_movements where item_id = $1`,
    args: [it],
  });
  assertEquals(m.rows[0].rt, "maintenance_ticket");
  assertEquals(m.rows[0].rid, ticketId);
  assertEquals(m.rows[0].q, -1);
  const expenses = (await su.queryObject<{ n: bigint }>({ text: `select count(*)::bigint n from expenses where facility_id=$1`, args: [facilityId] })).rows[0].n;
  assertEquals(Number(expenses.n ?? expenses), 0);
  await closeAll(su, c);
});

Deno.test("facility A cannot read or mutate facility B inventory", async () => {
  const su = await superuser();
  await resetCore(su);
  const a = await makeUser(su);
  const b = await makeUser(su);
  await makeFacility(su, a);
  const fb = await makeFacility(su, b);
  const bc = await authed(b);
  const catB = await category(bc, fb);
  const itB = await item(bc, fb, catB, 5);
  await bc.end();

  const ac = await authed(a);
  await assertRejects(() => ac.queryArray({ text: `select get_inventory_overview($1)`, args: [fb] }), Error, "permission");
  await assertRejects(() => ac.queryArray({ text: `select list_inventory_items($1)`, args: [fb] }), Error, "permission");
  await assertRejects(() => ac.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',1)`, args: [itB] }), Error);
  assertEquals(
    (await ac.queryObject<{ n: bigint }>({ text: `select count(*)::bigint n from inventory_items where facility_id = $1`, args: [fb] })).rows[0].n,
    0n,
  );
  await closeAll(su, ac);
});

Deno.test("staff with INVENTORY_VIEW but not INVENTORY_ADJUST cannot adjust stock", async () => {
  const su = await superuser();
  const { owner, facilityId } = await seed(su);
  const oc = await authed(owner);
  const cat = await category(oc, facilityId);
  const it = await item(oc, facilityId, cat, 10);
  await oc.end();

  const staff = await makeUser(su);
  await addStaff(su, facilityId, staff, "staff"); // staff default: VIEW + STOCK_IN + STOCK_OUT, NOT ADJUST
  const sc = await authed(staff);
  await assertRejects(
    () => sc.queryArray({ text: `select record_stock_movement($1,'ADJUSTMENT',-3,'count')`, args: [it] }),
    Error,
    "permission",
  );
  // but STOCK_OUT is allowed
  await sc.queryArray({ text: `select record_stock_movement($1,'STOCK_OUT',2)`, args: [it] });
  await closeAll(su, sc);
});
