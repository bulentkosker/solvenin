-- 055_fix_repair_ref_type.sql
-- Fix: reference_type must be 'sales_order'/'purchase_order' per chk_stock_mv_ref_type constraint.
-- 'repair' is not an allowed value.

BEGIN;

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
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

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
      WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, sales_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'sales_order');
    created_count := created_count + 1;
  END LOOP;

  SELECT COUNT(DISTINCT sm.sales_order_id) INTO orders_affected
  FROM stock_movements sm
  WHERE sm.company_id = p_company_id
  AND sm.notes = 'Stok Onarımı — Servis Paneli'
  AND sm.created_at > now() - interval '10 seconds';

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, affected_records, created_records, details)
  VALUES (p_company_id, 'missing_sales_stock', p_user_id, p_start, p_end, orders_affected, created_count, json_build_object('note', 'Sales stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'orders', orders_affected, 'created', created_count);
END;
$BODY$;

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
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

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
      WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, purchase_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'purchase_order');
    created_count := created_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, created_records, details)
  VALUES (p_company_id, 'missing_purchase_stock', p_user_id, p_start, p_end, created_count, json_build_object('note', 'Purchase stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

CREATE OR REPLACE FUNCTION sp_fix_single_sales_stock(p_company_id uuid, p_order_id uuid)
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
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT soi.product_id, soi.quantity, soi.warehouse_id, so.order_number
    FROM sales_orders so
    JOIN sales_order_items soi ON soi.order_id = so.id
    WHERE so.id = p_order_id AND so.company_id = p_company_id
    AND soi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, sales_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, p_order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'sales_order');
    created_count := created_count + 1;
  END LOOP;

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

CREATE OR REPLACE FUNCTION sp_fix_single_purchase_stock(p_company_id uuid, p_order_id uuid)
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
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT poi.product_id, poi.quantity, po.order_number
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.order_id = po.id
    WHERE po.id = p_order_id AND po.company_id = p_company_id
    AND poi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, purchase_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, p_order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'purchase_order');
    created_count := created_count + 1;
  END LOOP;

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('055_fix_repair_ref_type.sql',
  'Fix: reference_type repair→sales_order/purchase_order per chk_stock_mv_ref_type constraint')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
