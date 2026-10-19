-- ═══════════════════════════════════════════════════════════════════════════
-- Inventory > Categories: "structure of query does not match function result type"
-- (42804: Returned type numeric does not match expected type bigint in column 7).
--
-- list_inventory_categories declared inventory_value_minor as bigint, but sum() of a
-- bigint expression returns numeric, so Postgres refused to return the rows.
-- Recreated from 0081 with the sum cast back to bigint. Same signature and columns.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function list_inventory_categories(p_facility_id uuid)
returns table (
  id uuid, name text, description text, is_active boolean, sort_order integer,
  item_count bigint, inventory_value_minor bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  return query
  select c.id, c.name, c.description, c.is_active, c.sort_order,
    (select count(*) from inventory_items i where i.category_id = c.id) as item_count,
    coalesce((select sum(i.current_stock::bigint * i.unit_cost_minor)::bigint from inventory_items i
              where i.category_id = c.id and i.status = 'ACTIVE'), 0)::bigint as inventory_value_minor
  from inventory_categories c
  where c.facility_id = p_facility_id
  order by c.sort_order, c.name;
end;
$$;

grant execute on function list_inventory_categories(uuid) to authenticated;
