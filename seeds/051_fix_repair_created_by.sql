-- 051_fix_repair_created_by.sql
-- Fix stock_movements_created_by_fkey violation in repair functions.
-- created_by now set to company owner's auth.users ID instead of
-- relying on auth.uid() which is null in SECURITY DEFINER context.

BEGIN;

-- Sales stock repair
CREATE OR REPLACE FUNCTION sp_apply_missing_sales_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  orders_affected int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu
    WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true
  ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT DISTINCT so.id as order_id, so.order_number, soi.product_id, soi.quantity, soi.warehouse_id
    FROM sales_orders so
    JOIN sales_order_items soi ON soi.order_id = so.id
    WHERE so.company_id = p_company_id
    AND so.status IN ('invoiced','paid','overdue')
    AND so.is_active = true
    AND so.issue_date BETWEEN p_start AND p_end
    AND soi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.invoice_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, invoice_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  SELECT COUNT(DISTINCT so.id) INTO orders_affected FROM sales_orders so
  JOIN stock_movements sm ON sm.invoice_id = so.id
  WHERE so.company_id = p_company_id
  AND sm.reference_type = 'repair'
  AND sm.created_at > now() - interval '10 seconds';

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, affected_records, created_records, details)
  VALUES (p_company_id, 'missing_sales_stock', p_user_id, p_start, p_end, orders_affected, created_count, json_build_object('note', 'Sales stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'orders', orders_affected, 'created', created_count);
END;
$BODY$;

-- Purchase stock repair
CREATE OR REPLACE FUNCTION sp_apply_missing_purchase_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu
    WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true
  ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT po.id as order_id, po.order_number, poi.product_id, poi.quantity
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.order_id = po.id
    WHERE po.company_id = p_company_id
    AND po.status IN ('invoiced','paid','overdue','received')
    AND po.is_active = true
    AND po.issue_date BETWEEN p_start AND p_end
    AND poi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.invoice_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, invoice_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, created_records, details)
  VALUES (p_company_id, 'missing_purchase_stock', p_user_id, p_start, p_end, created_count, json_build_object('note', 'Purchase stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

-- Stock recalc (no stock_movements INSERT, but keep consistent p_user_id→repair_logs)
CREATE OR REPLACE FUNCTION sp_recalc_product_stock(p_user_id uuid, p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  updated_count int := 0;
  rec RECORD;
  new_qty numeric;
BEGIN
  FOR rec IN SELECT id FROM products WHERE company_id = p_company_id AND is_active = true LOOP
    SELECT COALESCE(SUM(CASE WHEN type = 'in' OR type = 'return' THEN quantity ELSE -quantity END), 0)
    INTO new_qty
    FROM stock_movements
    WHERE product_id = rec.id AND is_active = true AND company_id = p_company_id;

    UPDATE products SET quantity = new_qty WHERE id = rec.id;
    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, affected_records, details)
  VALUES (p_company_id, 'recalc_product_stock', p_user_id, updated_count, json_build_object('note', 'Product quantities recalculated')::jsonb);

  RETURN json_build_object('ok', true, 'updated', updated_count);
END;
$BODY$;

-- Also add reference_type column if missing
ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS reference_type varchar(50) DEFAULT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('051_fix_repair_created_by.sql',
  'Fix FK violation: repair functions now use company owner ID as created_by + reference_type=repair')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
